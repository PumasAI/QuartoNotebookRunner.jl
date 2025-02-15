module QuartoNotebookWorkerPythonCallExt

# Imports.

import PythonCall as PC
import QuartoNotebookWorker

# Python imports.

ast_mod() = PC.@pyconst(PC.pyimport("ast"))
io_mod() = PC.@pyconst(PC.pyimport("io"))
sys_mod() = PC.@pyconst(PC.pyimport("sys"))
tokenize_mod() = PC.@pyconst(PC.pyimport("tokenize"))

# Conversions.

function convert_py(value::PC.Py)
    # So that `nothing`-equivalent values are returned as `nothing` which will
    # then not echo a value in the notebook.
    if PC.pyis(value, PC.pybuiltins.None)
        return nothing
    else
        # TODO: Potentially other conversions are needed here.
        return value
    end
end
convert_py(value) = value

"""
    eval_code(m::Module, code::String)

Evalute the Python `code` string in the given module `m`.

This requires any interpolated global variables to have been set in the module
prior to calling. Use `assign_globals` for that.
"""
function eval_code(m::Module, code::String)
    # During evaluation we point Python's `stdout` and `stderr` to the Julia
    # `stdout` and `stderr` streams such that `IOCapture` can capture the
    # output. It works without this when the Julia process is interactive, e.g.
    # it's been started via `QuartoNotebookRunner.WorkerSetup.debug()`, but
    # when run properly in a notebook process it did not get captured
    # correctly.
    sys = sys_mod()
    py_stdout = sys.stdout
    py_stderr = sys.stderr
    # Use a `pytextio` otherwise we get "memoryview: a bytes-like object is
    # required, not 'str'" errors.
    sys.stdout = PC.pytextio(stdout)
    sys.stderr = PC.pytextio(stderr)

    result = nothing
    try
        # Parse the code such that we can return a final value from the cell.
        ast = ast_mod()
        tree = ast.parse(code)
        toplevel = collect(tree.body)
        total = length(toplevel)
        for (nth, each) in enumerate(toplevel)
            if nth == total && PC.pyisinstance(each, ast.Expr)
                # Ideally we want to replicate the behavour of the Python and
                # IPython REPLs closely, which is shown below:
                #
                #     >>> a = 1
                #     >>> a
                #     1
                #
                #     In [1]: a = 1
                #
                #     In [2]: a
                #     Out[2]: 1
                #
                # Note that assignments do not return the value of the
                # assignment, since they are not expressions.
                #
                # TODO: any other ast nodes that return values?
                result = PC.pyeval(ast.unparse(each), m)
            else
                PC.pyexec(ast.unparse(each), m)
            end
        end
    finally
        # Ensure that the Python `stdout` and `stderr` streams are restored at
        # the end of evaluation.
        sys.stdout = py_stdout
        sys.stderr = py_stderr
    end
    return convert_py(result)
end

"""
    assign_globals(m::Module, nt::NamedTuple)

Assigns the values in the named tuple `nt` to the global variables in the
module `m`. These are interpolated global variables/expressions that are
evaluated in Julia and then passed to Python where they are referenced in the
Python code to be evaluated. `eval_code` is used to evaluate the Python code.
"""
function assign_globals(m::Module, nt::NamedTuple)
    if !isempty(nt)
        globals = join(keys(nt), ", ")
        # The way that the elements are unpacked from `vals` means that we need
        # to run different code for a single value vs multiple values.
        vals = length(nt) < 2 ? "= vals[0]" : "= vals"
        code = string("global ", globals, "; ", globals, vals)
        PC.pyexec(code, m, (; vals = values(nt)))
    end
    return nothing
end

"""
    QuartoNotebookWorker._py_expr(::Nothing, code::AbstractString)

The `QuartoNotebookWorker._py_expr` function is used to parse the Python code
and turn in into a Julia expression that is then run with `Core.eval`.

See `src/python.jl` for the entrypoint function for this code. The indirection
allows for loading this code only when `PythonCall` is available without
needing to manually check for the existence of the package on each call. When
not loaded the less specific method with an `::Any` argument is called, which
simply throws an error that `PythonCall` needs to be loaded by the user.
"""
function QuartoNotebookWorker._py_expr(::Nothing, code::AbstractString)
    # Swap out all `$` characters in the code with a unique string that we can
    # use to identify them during tokenisation. During tokenisation we parse
    # all found `$` interpolations using Julia's `Meta.parse`. `$`s that are
    # not part of a Python variable (e.g. inside a string) are ignored. We then
    # build up a new code string that replaces the valid interpolations with
    # unique variable names that we can use to reference the parsed
    # expressions. The parsed expressions are then assigned to these variables
    # in the Python module before the code is evaluated.

    uid = string(rand(UInt16); base = 62)
    key = "___DOLLAR$(uid)___"
    skey = Symbol(key)
    escaped_code = replace(code, "\$" => key)

    # When there are no `$` characters in the code, we can bypass all the
    # preprocessing steps and just evaluate the original code. This skips
    # tokenisation step and interpolation generation.
    if escaped_code == code
        return quote
            $(eval_code)($(QuartoNotebookWorker.NotebookState.notebook_module)(), $(code))
        end
    end

    # A reverse lookup to allow finding the original `$` in the code based on
    # the token offset of the escaped code.
    dollar_indices = findall(isequal('$'), code)
    escaped_indices = [m.offset for m in eachmatch(Regex(key), escaped_code)]
    index_lookup = Dict(e => d for (e, d) in zip(escaped_indices, dollar_indices))

    interpolated_expressions = []
    interp_count = 0
    interpolated_code = IOBuffer()

    current_index = 1

    units = codeunits(escaped_code)
    byte_stream = io_mod().BytesIO(units)

    # The offset calculation function is used to convert from a row/column
    # location in the token stream to the offset in the original string.
    get_offset = offset_func(escaped_code)

    for token in tokenize_mod().tokenize(byte_stream.readline)
        token_type = PC.pyconvert(Int, token.type)
        token_string = PC.pyconvert(String, token.string)

        # We've encounted a `$` in the token stream. Token type 1 is a NAME.
        if token_type == 1 && startswith(token_string, key)
            row, column = row_column(token)
            offset_begin = get_offset(row, column)

            index = index_lookup[offset_begin]
            print(interpolated_code, SubString(code, current_index, index - 1))

            # Parse the next expression using Julia.
            ex, offset = Meta.parse(escaped_code, offset_begin; greedy = false)

            # Either it's just a `$`, in which case we need to parse
            # the expression afterwards, since that will be a `()` expression.
            ex, offset = if ex === skey
                char = escaped_code[offset]
                if char == '('
                    Meta.parse(escaped_code, offset; greedy = false)
                else
                    error("invalid interpolation syntax.")
                end
            else
                # Or it is a `$varname`, which will parse as a single `Symbol`.
                # We keep the same offset value in this case since nothing else
                # has been parsed.
                Symbol(replace(String(ex), key => ""; count = 1)), offset
            end

            varname = Symbol("__INTERP$(uid)_", (interp_count += 1), "__")
            print(interpolated_code, varname)
            push!(interpolated_expressions, Expr(:kw, varname, ex))

            escaped_interp_width = offset - offset_begin
            width = escaped_interp_width - length(key) + 1
            current_index = index + width
        end
    end
    print(interpolated_code, SubString(code, current_index))

    interpolated_variables = :(; $(interpolated_expressions...))
    final_code = String(take!(interpolated_code))

    nb_mod = QuartoNotebookWorker.NotebookState.notebook_module
    quote
        $(assign_globals)($(nb_mod)(), $(interpolated_variables))
        $(eval_code)($(nb_mod)(), $(final_code))
    end
end

# Checks whether the Python token is a variable beginning with a `$`.
function is_dollar(token, key)
    type = PC.pyconvert(Int, token.type)
    if type == 1
        string = PC.pyconvert(String, token.string)
        return startswith(string, key)
    else
        return false
    end
end

# Unpacks the row and column from the Python token. The column is 0-based so
# adjust it to be 1-based for use in Julia.
function row_column(token)
    row, column = PC.pyconvert(Tuple{Int,Int}, token.start)
    column += 1
    return row, column
end

# Creates a lookup function that converts from a row/column token location to
# the offset in the original string.
function offset_func(text::AbstractString)
    lines = collect(eachline(IOBuffer(text); keep = true))
    nlines = length(lines)
    return function (row::Integer, column::Integer)
        1 <= row <= nlines || error("`row = $row` is out of bounds.")
        1 <= column <= length(lines[row]) || error("`column = $column` is out of bounds.")
        if row == 1
            return column
        else
            # TODO: lift into outer function.
            return sum(length(lines[r]) for r = 1:(row-1)) + column
        end
    end
end

end
