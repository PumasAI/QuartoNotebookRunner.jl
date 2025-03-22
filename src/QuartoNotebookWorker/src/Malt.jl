module Malt

import QuartoNotebookWorker.Packages.BSON

using Logging: Logging, @debug
using Sockets: Sockets

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        Base.exit_on_sigint(false)
    end
    return nothing
end

include("shared.jl")

function main()
    # Use the same port hint as Distributed
    port_hint = 9000 + (Sockets.getpid() % 1000)
    port, server = Sockets.listenany(port_hint)

    # Write port number to stdout to let main process know where to send requests
    @debug("WORKER: new port", port)
    println(stdout, port)
    flush(stdout)

    # Set network parameters, this is copied from Distributed
    Sockets.nagle(server, false)
    Sockets.quickack(server, true)

    serve(server)
end

function serve(server::Sockets.TCPServer)

    # Wait for new request
    @debug("WORKER: Waiting for new connection")
    io = Sockets.accept(server)
    @debug("WORKER: New connection", io)

    # Set network parameters, this is copied from Distributed
    Sockets.nagle(io, false)
    Sockets.quickack(io, true)
    _buffer_writes(io)

    # Here we use:
    # `for _i in Iterators.countfrom(1)`
    # instead of
    # `while true`
    # as a workaround for https://github.com/JuliaLang/julia/issues/37154
    for _i in Iterators.countfrom(1)
        if !isopen(io)
            @debug("WORKER: io closed.")
            break
        end
        @debug "WORKER: Waiting for message"
        msg_type = try
            if eof(io)
                @debug("WORKER: io closed.")
                break
            end
            read(io, UInt8)
        catch e
            if e isa InterruptException
                @debug("WORKER: Caught interrupt while waiting for incoming data, ignoring...")
                continue # and go back to waiting for incoming data
            else
                @error(
                    "WORKER: Caught exception while waiting for incoming data, breaking",
                    exception = (e, backtrace())
                )
                break
            end
        end
        # this next line can't fail
        msg_id = read(io, MsgID)

        msg_data, success = try
            (Base.invokelatest(_bson_deserialize, io), true)
        catch err
            (format_error(err, catch_backtrace()), false)
        finally
            _discard_until_boundary(io)
        end

        if !success
            if msg_type === MsgType.from_host_call_with_response
                msg_type = MsgType.special_serialization_failure
            else
                continue
            end
        end

        try
            @debug("WORKER: Received message", msg_data)
            handle(Val(msg_type), io, msg_data, msg_id)
            @debug("WORKER: handled")
        catch e
            if e isa InterruptException
                @debug("WORKER: Caught interrupt while handling message, ignoring...")
            else
                @error(
                    "WORKER: Caught exception while handling message, ignoring...",
                    exception = (e, backtrace())
                )
            end
            handle(Val(MsgType.special_serialization_failure), io, e, msg_id)
        end
    end

    @debug("WORKER: Closed server socket. Bye!")
end

# Check if task is still running before throwing interrupt
interrupt(t::Task) = istaskdone(t) || Base.schedule(t, InterruptException(); error = true)
interrupt(::Nothing) = nothing


function handle(::Val{MsgType.from_host_call_with_response}, socket, msg, msg_id::MsgID)
    f, args, kwargs, respond_with_nothing = msg

    @async begin
        result, success = try
            result = f(args...; kwargs...)

            # @debug("WORKER: Evaluated result", result)
            (respond_with_nothing ? nothing : result, true)
        catch err
            # @debug("WORKER: Got exception!", e)
            (format_error(err, catch_backtrace()), false)
        end

        _serialize_msg(
            socket,
            success ? MsgType.from_worker_call_result : MsgType.from_worker_call_failure,
            msg_id,
            result,
        )
    end
end


function handle(::Val{MsgType.from_host_call_without_response}, socket, msg, msg_id::MsgID)
    f, args, kwargs, _ignored = msg

    @async try
        f(args...; kwargs...)
    catch e
        @warn(
            "WORKER: Got exception while running call without response",
            exception = (e, catch_backtrace())
        )
        # TODO: exception is ignored, is that what we want here?
    end
end

function handle(::Val{MsgType.special_serialization_failure}, socket, msg, msg_id::MsgID)
    _serialize_msg(socket, MsgType.from_worker_call_failure, msg_id, msg)
end

format_error(err, bt) =
    sprint() do io
        Base.invokelatest(showerror, io, err, bt)
    end

const _channel_cache = Dict{UInt64,AbstractChannel}()

end
