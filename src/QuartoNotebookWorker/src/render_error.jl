# Error formatting and backtrace cleaning.

function clean_bt_str(is_error::Bool, bt, err, prefix = "", mimetype = false)
    is_error || return UInt8[]

    # Only include the first encountered `top-level scope` in the
    # backtrace, since that's the actual notebook code. The rest is just
    # the worker code.
    bt = Base.scrub_repl_backtrace(bt)
    top_level = findfirst(x -> x.func === Symbol("top-level scope"), bt)
    bt = bt[1:something(top_level, length(bt))]

    if mimetype
        non_worker = findfirst(_non_worker_stackframe_marker, bt)
        bt = bt[1:max(something(non_worker, length(bt)) - 1, 0)]
    end

    buf = IOBuffer()
    buf_context = with_context(buf)
    print(buf_context, prefix)
    _showerror(buf_context, err, bt)

    return take!(buf)
end

# `PythonCall` extension needs to override this part of stacktrace printing so
# that it can print out just the Python part of the stacktrace. See the
# `ext/QuartoNotebookWorkerPythonCall.jl` file for that implementation.
function _showerror(io::IO, err, bt)
    Base.showerror(io, err)
    Base.show_backtrace(io, bt)
end

_non_worker_stackframe_marker(frame) =
    contains(String(frame.file), @__FILE__) &&
    frame.func in (:__print_barrier__, :__show_barrier__)
