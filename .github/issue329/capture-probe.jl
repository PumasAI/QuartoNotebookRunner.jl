# The kaleido probe's backtrace put the hang in `IOCapture`'s cleanup, waiting
# for its pipe to reach EOF while the process the cell started still held the
# write end. This probe has no plotting package in it: the child writes a
# handshake, then either exits or lingers, and lingering is what should hang.

using Pkg

Pkg.activate(mktempdir())
Pkg.add("IOCapture")

using IOCapture

bytes = parse(Int, get(ENV, "PROBE_BYTES", "1000"))
stream = get(ENV, "PROBE_STREAM", "stderr")
linger = parse(Int, get(ENV, "PROBE_LINGER", "0"))

child_code = """
    write($(stream), repeat("x", $(bytes)))
    flush($(stream))
    println(stdout, "READY")
    flush(stdout)
    sleep($(linger))
    """

println("child writes $(bytes) bytes to $(stream), then lives $(linger)s")
flush(stdout)

captured = IOCapture.capture() do
    # `stderr` and `stdout` here are the capture's own streams, so the child
    # inherits them the same way a cell's child process does.
    child = open(pipeline(`$(Base.julia_cmd()) -e $(child_code)`; stderr), "r")
    return readline(child)
end

println("handshake: $(captured.value)")
println("capture collected $(ncodeunits(captured.output)) bytes")
