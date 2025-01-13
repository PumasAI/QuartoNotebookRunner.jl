
import Distributed

const Distributed_expr = quote
    Base.loaded_modules[Base.PkgId(Base.UUID("8ba89e20-285c-5b6f-9357-94700520ee1b"), "Distributed")]
end

"""
    Malt.DistributedStdlibWorker()

This implements the same functions as `Malt.Worker` but it uses the Distributed stdlib as a backend. Can be used for backwards compatibility.
"""
mutable struct DistributedStdlibWorker <: AbstractWorker
    pid::Int64
    isrunning::Bool

    function DistributedStdlibWorker(; env=String[], exeflags=[])
        # Spawn process
        expr = if VERSION < v"1.9.0-aaa"
            isempty(env) || @warn "Malt.DistributedStdlibWorker: the `env` kwarg requires Julia 1.9"
            :($(Distributed_expr).addprocs(1; exeflags=$(exeflags)) |> first)
        else
            :($(Distributed_expr).addprocs(1; exeflags=$(exeflags), env=$(env)) |> first)
        end
        pid = Distributed.remotecall_eval(Main, 1, expr)

        # TODO: process preamble from Pluto?

        # There's no reason to keep the worker process alive after the manager loses its handle.
        w = finalizer(w -> @async(stop(w)),
            new(pid, true)
        )
        atexit(() -> stop(w))

        return w
    end
end

Base.summary(io::IO, w::DistributedStdlibWorker) = write(io, "Malt.DistributedStdlibWorker with pid $(w.pid)")


macro transform_exception(worker, ex)
    :(try
        $(esc(ex))
    catch e
        if e isa Distributed.RemoteException
            throw($(RemoteException)($(esc(worker)), sprint(showerror, e.captured)))
        else
            rethrow(e)
        end
    end)
end

function remote_call(f, w::DistributedStdlibWorker, args...; kwargs...)
    @async Distributed.remotecall_fetch(f, w.pid, args...; kwargs...)
end

function remote_call_fetch(f, w::DistributedStdlibWorker, args...; kwargs...)
    @transform_exception w Distributed.remotecall_fetch(f, w.pid, args...; kwargs...)
end

function remote_call_wait(f, w::DistributedStdlibWorker, args...; kwargs...)
    @transform_exception w Distributed.remotecall_wait(f, w.pid, args...; kwargs...)
    nothing
end

function remote_do(f, w::DistributedStdlibWorker, args...; kwargs...)
    Distributed.remote_do(f, w.pid, args...; kwargs...)
end

function worker_channel(w::DistributedStdlibWorker, expr)
    @transform_exception w Core.eval(Main, quote
        $(Distributed).RemoteChannel(() -> Core.eval(Main, $(QuoteNode(expr))), $(w.pid))
    end)
end

isrunning(w::DistributedStdlibWorker) = w.isrunning

function stop(w::DistributedStdlibWorker)
    w.isrunning = false
    Distributed.remotecall_eval(Main, 1, quote
        $(Distributed_expr).rmprocs($(w.pid)) |> wait
    end)
    nothing
end

Base.kill(w::DistributedStdlibWorker, signum=Base.SIGTERM) = error("not implemented for DistributedStdlibWorker")

function interrupt(w::DistributedStdlibWorker)
    if Sys.iswindows()
        @warn "Malt.interrupt is not supported on Windows for a DistributedStdlibWorker"
        nothing
    else
        Distributed.interrupt(w.pid)
    end
end
