# Worker-side IPC server for QuartoNotebookRunner.

module WorkerIPC

import QuartoNotebookWorker
import Logging
import Sockets

include("protocol.jl")

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        Base.exit_on_sigint(false)
    end
    return nothing
end

function main()
    port_hint = 9000 + (Sockets.getpid() % 1000)
    port, server = Sockets.listenany(port_hint)

    Logging.@debug "WORKER: listening on port $port"
    println(stdout, port)
    flush(stdout)

    Sockets.nagle(server, false)
    Sockets.quickack(server, true)

    serve(server)
end

function serve(server::Sockets.TCPServer)
    Logging.@debug "WORKER: waiting for connection"
    socket = Sockets.accept(server)
    Logging.@debug "WORKER: connected"

    Sockets.nagle(socket, false)
    Sockets.quickack(socket, true)

    # Wrap in LockableIO for thread-safe writes
    io = LockableIO(socket)

    # Send handshake
    write_handshake(io)

    # Message loop - use countfrom as workaround for Julia issue #37154
    for _ in Iterators.countfrom(1)
        isopen(io.io) || break

        msg = try
            eof(io.io) && break
            read_message(io)
        catch e
            if e isa InterruptException
                Logging.@debug "WORKER: interrupted while reading, continuing"
                continue
            elseif e isa EOFError || e isa Base.IOError
                Logging.@debug "WORKER: connection closed"
                break
            else
                Logging.@error "WORKER: read error" exception = (e, catch_backtrace())
                break
            end
        end

        # Handle shutdown
        if msg.type == MsgType.SHUTDOWN
            Logging.@debug "WORKER: received shutdown"
            break
        end

        # Handle call
        if msg.type == MsgType.CALL
            handle_call(io, msg)
        else
            Logging.@warn "WORKER: unknown message type" msg.type
        end
    end

    Logging.@debug "WORKER: exiting"
end

function handle_call(io::LockableIO, msg::Message)
    # Deserialize request
    request = try
        Base.invokelatest(_ipc_deserialize, msg.payload)
    catch e
        send_error(io, msg.id, e)
        return
    end

    # Dispatch to worker function
    result, success = try
        (Base.invokelatest(QuartoNotebookWorker.dispatch, request), true)
    catch e
        (format_error(e, catch_backtrace()), false)
    end

    # Send response
    msg_type = success ? MsgType.RESULT_OK : MsgType.RESULT_ERR
    payload = try
        Base.invokelatest(_ipc_serialize, result)
    catch e
        msg_type = MsgType.RESULT_ERR
        Base.invokelatest(_ipc_serialize, format_error(e, catch_backtrace()))
    end

    try
        write_message(io, Message(msg_type, msg.id, payload))
    catch e
        Logging.@error "WORKER: failed to send response" exception = (e, catch_backtrace())
    end
end

function send_error(io::LockableIO, msg_id::MsgID, err)
    payload = Base.invokelatest(_ipc_serialize, format_error(err, catch_backtrace()))
    try
        write_message(io, Message(MsgType.RESULT_ERR, msg_id, payload))
    catch
    end
end

function format_error(err, bt)
    sprint() do io
        Base.invokelatest(showerror, io, err, bt)
    end
end

end # module
