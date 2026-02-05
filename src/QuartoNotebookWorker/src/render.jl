# Core cell rendering.

function render(
    code::AbstractString,
    file::AbstractString,
    line::Integer,
    cell_options::AbstractDict = Dict{String,Any}();
    inline::Bool = false,
    mod::Module,
)
    # This records whether the outermost cell is an expandable cell, which we
    # then return to the server so that it can decide whether to treat the cell
    # results it gets back as an expansion or not. We can't decide this
    # statically since expansion depends on whether the runtime type of the cell
    # output is `is_expandable` or not. Recursive calls to `_render_thunk` don't
    # matter to the server, it's just the outermost cell that matters.
    is_expansion_ref = Ref(false)
    cells = NotebookState.with_notebook_module(mod) do
        Base.@invokelatest(
            collect(
                _render_thunk(code, mod, cell_options, is_expansion_ref; inline) do
                    Base.@invokelatest include_str(mod, code; file, line, cell_options)
                end,
            )
        )
    end
    return WorkerIPC.RenderResponse(cells, is_expansion_ref[])
end

# Recursively render cell thunks. This might be an `include_str` call,
# which is the starting point for a source cell, or it may be a
# user-provided thunk that comes from a source cell with `expand` set
# to `true`.
function _render_thunk(
    thunk::Base.Callable,
    code::AbstractString,
    mod::Module,
    cell_options::AbstractDict = Dict{String,Any}(),
    is_expansion_ref::Ref{Bool} = Ref(false);
    inline::Bool,
)
    captured, display_results = NotebookState.with_cell_options(cell_options) do
        with_inline_display(thunk, cell_options)
    end

    # Attempt to expand the cell. This requires the cell result to have a method
    # defined for the `QuartoNotebookWorker.expand` function. We only attempt to
    # run expansion if the cell didn't error. Cell expansion can itself error,
    # so we need to catch that and return an error cell if that's the case.
    expansion = nothing
    is_expansion = false
    if !captured.error
        try
            expansion = Base.@invokelatest expand(captured.value)
            is_expansion = _is_expanded(captured.value, expansion)
        catch error
            backtrace = catch_backtrace()
            return (
                WorkerIPC.CellResult(
                    "", # an expanded cell that errored can't have returned code
                    Dict{String,Any}(), # or options
                    Dict{String,WorkerIPC.MimeResult}(),
                    display_results,
                    captured.output,
                    string(typeof(error)),
                    collect(eachline(IOBuffer(clean_bt_str(true, backtrace, error, mod)))),
                ),
            )
        end
        # Track in this side-channel whether the cell is an expansion or not.
        is_expansion_ref[] = is_expansion
    end

    if is_expansion
        # A cell expansion with `expand` might itself also contain
        # cells that expand to multiple cells, so we need to flatten
        # the results to a single list of cells before passing back
        # to the server. Cell expansion is recursive.
        return _flatmap(expansion) do cell
            wrapped = function ()
                return io_capture(
                    cell.thunk;
                    cell_options = cell.options,
                    rethrow = InterruptException,
                    color = true,
                )
            end
            # **The recursive call:**
            return Base.@invokelatest _render_thunk(
                wrapped,
                cell.code,
                mod,
                cell.options;
                inline,
            )
        end
    else
        results = Base.@invokelatest render_mimetypes(
            REPL.ends_with_semicolon(code) ? nothing : captured.value,
            mod,
            cell_options;
            inline,
        )
        # Wrap in a Tuple to avoid being flattened when passed into
        # `flatmap` and `collect`.
        return (
            WorkerIPC.CellResult(
                code,
                Dict{String,Any}(cell_options),
                results,
                display_results,
                captured.output,
                captured.error ? string(typeof(captured.value)) : nothing,
                collect(
                    eachline(
                        IOBuffer(
                            clean_bt_str(
                                captured.error,
                                captured.backtrace,
                                captured.value,
                                mod,
                            ),
                        ),
                    ),
                ),
            ),
        )
    end
end
