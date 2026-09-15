# `PlotlyKaleido.start()` is the line of the issue 329 notebook that stops on
# Windows. This probe calls it outside quarto and outside the notebook worker,
# either bare or inside the same IO capture a cell's code runs under, to find
# out whether the runner is involved at all.

using Pkg

Pkg.activate(mktempdir())
Pkg.add("PlotlyKaleido")
Pkg.add("IOCapture")

using PlotlyKaleido
using IOCapture

mode = get(ENV, "PROBE_MODE", "bare")

# The capture mode hangs on Windows, so print every task's backtrace before the
# deadline kills the process. This needs a second thread: the stuck task is the
# one that would otherwise run the watchdog.
watchdog = parse(Int, get(ENV, "PROBE_WATCHDOG", "0"))
if watchdog > 0
    Threads.@spawn begin
        sleep(watchdog)
        ccall(:jl_print_task_backtraces, Cvoid, (Cint,), 0)
        flush(stdout)
        flush(stderr)
        exit(2)
    end
end

println("calling PlotlyKaleido.start() in $mode mode")
flush(stdout)

if mode == "capture"
    captured = IOCapture.capture() do
        PlotlyKaleido.start()
    end
    print(captured.output)
else
    PlotlyKaleido.start()
end

println("kaleido started")
PlotlyKaleido.kill_kaleido()
println("kaleido stopped")
