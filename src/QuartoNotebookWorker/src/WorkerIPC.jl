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
    QuartoNotebookWorker.with_diagnostic_logger(; prefix = "worker") do
        port_hint = 9000 + (Sockets.getpid() % 1000)
        port, server = Sockets.listenany(port_hint)

        Logging.@debug "Listening on port $port"
        println(stdout, port)
        flush(stdout)

        Sockets.nagle(server, false)
        Sockets.quickack(server, true)

        serve(server)
    end
end

function serve(server::Sockets.TCPServer)
    Logging.@debug "Waiting for connection"
    socket = Sockets.accept(server)
    Logging.@debug "Connected"

    Sockets.nagle(socket, false)
    Sockets.quickack(socket, true)

    # Wrap in LockableIO for thread-safe writes
    io = LockableIO(socket)

    # Send handshake
    write_handshake(io)

    # Local contexts dict for multi-notebook support
    contexts = Dict{String,QuartoNotebookWorker.NotebookState.NotebookContext}()
    contexts_lock = ReentrantLock()

    # Message loop - use countfrom as workaround for Julia issue #37154
    for _ in Iterators.countfrom(1)
        isopen(io.io) || break

        msg = try
            eof(io.io) && break
            read_message(io)
        catch e
            if e isa InterruptException
                Logging.@debug "Interrupted while reading, continuing"
                continue
            elseif e isa EOFError || e isa Base.IOError
                Logging.@debug "Connection closed"
                break
            else
                Logging.@error "Read error" exception = (e, catch_backtrace())
                break
            end
        end

        # Handle shutdown
        if msg.type == MsgType.SHUTDOWN
            Logging.@debug "Received shutdown"
            break
        end

        # Handle call
        if msg.type == MsgType.CALL
            handle_call(io, msg, contexts, contexts_lock)
        else
            Logging.@warn "Unknown message type" msg.type
        end
    end

    Logging.@debug "Exiting"
end

function handle_call(
    io::LockableIO,
    msg::Message,
    contexts::Dict{String,QuartoNotebookWorker.NotebookState.NotebookContext},
    contexts_lock::ReentrantLock,
)
    # Deserialize request
    request = try
        _ipc_deserialize(msg.payload)
    catch e
        send_error(io, msg.id, e)
        return
    end

    Logging.@debug "Handling request" request_type = nameof(typeof(request))

    result, success = try
        (QuartoNotebookWorker.dispatch(request, contexts, contexts_lock), true)
    catch e
        (format_error(e, catch_backtrace()), false)
    end

    # Send response
    msg_type = success ? MsgType.RESULT_OK : MsgType.RESULT_ERR
    payload = try
        _ipc_serialize(result)
    catch e
        msg_type = MsgType.RESULT_ERR
        try
            _ipc_serialize(format_error(e, catch_backtrace()))
        catch
            _ipc_serialize("Internal error: failed to serialize error")
        end
    end

    try
        write_message(io, Message(msg_type, msg.id, payload))
    catch e
        Logging.@error "Failed to send response" exception = (e, catch_backtrace())
    end
end

function send_error(io::LockableIO, msg_id::MsgID, err)
    payload = try
        _ipc_serialize(format_error(err, catch_backtrace()))
    catch
        _ipc_serialize("Internal error: failed to serialize error")
    end
    try
        write_message(io, Message(MsgType.RESULT_ERR, msg_id, payload))
    catch
    end
end

function format_error(err, bt)
    try
        sprint(showerror, err, bt)
    catch
        "Error formatting failed: $(typeof(err))"
    end
end

end # module
