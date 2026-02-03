# Code processing and evaluation.

function _helpmode(code::AbstractString, mod::Module)
    @static if VERSION < v"1.11.0"
        # Earlier versions of Julia don't have the `helpmode` method that takes
        # `io`, `code`, `mod` and so we have to manually alter the returned
        # expression instead.
        ex = REPL.helpmode(code)
        ex = postwalk(ex) do x
            return x == Main ? mod : x
        end
        # helpmode embeds object references to `stdout` into the expression, but
        # since we are capturing the output it refers to a different stream. We
        # need to replace the first `stdout` reference with `:stdout` and remove
        # the argument from the other call so that it uses the redirected one.
        ex.args[2] = :stdout
        deleteat!(ex.args[end].args, 3)
        return ex
    else
        return :(Core.eval($(mod), $(REPL).helpmode(stdout, $(code), $(mod))))
    end
end

function _process_code(
    mod::Module,
    code::AbstractString;
    filename::AbstractString,
    lineno::Integer,
)
    help_regex = r"^\s*\?"
    if startswith(code, help_regex)
        code = String(chomp(replace(code, help_regex => ""; count = 1)))
        ex = _helpmode(code, mod)
        return Expr(:toplevel, ex)
    end

    shell_regex = r"^\s*;"
    if startswith(code, shell_regex)
        code = String(chomp(replace(code, shell_regex => ""; count = 1)))
        ex = :($(Base).@cmd($code))

        # Force the line numbering of macroexpansion errors to match the
        # location in the notebook cell where the shell command was
        # written.
        ex.args[2] = LineNumberNode(lineno, filename)

        return Expr(:toplevel, :($(Base).run($ex)), nothing)
    end

    pkg_regex = r"^\s*\]"
    if startswith(code, pkg_regex)
        code = String(chomp(replace(code, pkg_regex => ""; count = 1)))
        return Expr(:toplevel, :(
            let printed = $(Pkg).REPLMode.PRINTED_REPL_WARNING[]
                $(Pkg).REPLMode.PRINTED_REPL_WARNING[] = true
                try
                    $(Pkg).REPLMode.@pkg_str $code
                finally
                    $(Pkg).REPLMode.PRINTED_REPL_WARNING[] = printed
                end
            end
        ))
    end

    return _parseall(code; filename, lineno)
end

function include_str(
    mod::Module,
    code::AbstractString;
    file::AbstractString,
    line::Integer,
    cell_options::AbstractDict,
)
    loc = LineNumberNode(line, Symbol(file))
    try
        ast = _process_code(mod, code; filename = file, lineno = line)
        @assert Meta.isexpr(ast, :toplevel)
        # Note: IO capturing combines stdout and stderr into a single
        # `.output`, but Jupyter notebook spec appears to want them
        # separate. Revisit this if it causes issues.
        return io_capture(;
            cell_options = cell_options,
            rethrow = InterruptException,
            color = true,
            io_context = _io_context(cell_options),
        ) do
            result = nothing
            line_and_ex = Expr(:toplevel, loc, nothing)
            try
                for ex in ast.args
                    if ex isa LineNumberNode
                        loc = ex
                        line_and_ex.args[1] = ex
                        continue
                    end
                    # Wrap things to be eval'd in a :toplevel expr to carry line
                    # information as part of the expr.
                    line_and_ex.args[2] = ex
                    for transform in REPL.repl_ast_transforms
                        line_and_ex = Base.@invokelatest transform(line_and_ex)
                    end
                    result = Core.eval(mod, line_and_ex)
                    run_post_eval_hooks()
                end
            catch error
                run_post_eval_hooks()
                run_post_error_hooks()
                rethrow(error)
            end
            return result
        end
    catch err
        if err isa Base.Meta.ParseError
            return (;
                result = err,
                output = "",
                error = true,
                backtrace = catch_backtrace(),
            )
        else
            rethrow(err)
        end
    end
end
