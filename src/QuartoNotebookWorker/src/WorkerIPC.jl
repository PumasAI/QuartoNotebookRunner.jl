# Worker-side IPC server for QuartoNotebookRunner.

module WorkerIPC

import QuartoNotebookWorker
import Logging
import Sockets

include("protocol.jl")

# True in a session that opted into serving via `serve!`, false in a spawned
# worker. The two run the same dispatch code, so this is how a serving REPL
# knows to surface per-render feedback that a spawned worker suppresses.
const _SERVING = Ref(false)

# Serializes render dispatch across connections. A serving session accepts
# concurrent host connections, but renders mutate process-global state (the
# working directory, active project, environment), so only one runs at a time.
# Uncontended in a spawned worker, which serves a single connection.
const _RENDER_LOCK = ReentrantLock()

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
    serve_connection(socket)
end

# One host connection: handshake, then the message loop until shutdown or
# disconnect. Notebook contexts are scoped to the connection, so a host that
# reconnects starts from fresh notebook state in a warm process.
function serve_connection(socket::Sockets.TCPSocket)
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
        Base.lock(_RENDER_LOCK) do
            (QuartoNotebookWorker.dispatch(request, contexts, contexts_lock), true)
        end
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

# In-process worker server for attach mode.
#
# A live Julia session (typically an interactive REPL) serves the worker
# protocol so `quarto render` evaluates notebooks in this process instead of a
# spawned one. The session registers itself in the attach registry; the host
# finds it there when a notebook opts in with `julia.attach: true`.

mutable struct AttachServer
    port::Int
    root::String
    server::Sockets.TCPServer
    entry::String
    task::Union{Task,Nothing}
end

function Base.show(io::IO, ::MIME"text/plain", s::AttachServer)
    print(io, "QuartoNotebookWorker.AttachServer")
    if !isopen(s.server)
        print(io, " (stopped)")
        return
    end
    print(io, " (running)")
    print(io, "\n  port: ", s.port)
    print(io, "\n  root: ", s.root)
end

function Base.close(s::AttachServer)
    close(s.server)
    rm(s.entry; force = true)
    return nothing
end

# The directory this session serves: the enclosing git root, so any notebook
# in the repository can attach, else the directory itself. A `.git` path test
# covers worktrees, where `.git` is a file.
function _attach_root(dir::String = pwd())
    d = abspath(dir)
    while true
        ispath(joinpath(d, ".git")) && return d
        parent = dirname(d)
        parent == d && return abspath(dir)
        d = parent
    end
end

function serve!(; root::String = _attach_root())
    _SERVING[] = true
    # Renders activate the notebook's project, which need not carry
    # QuartoNotebookWorker. Spawned workers keep the package resolvable by
    # pushing its environment onto LOAD_PATH in startup.jl; uphold the same
    # invariant here so notebook modules can always import it.
    project = pkgdir(QuartoNotebookWorker)
    project in LOAD_PATH || push!(LOAD_PATH, project)

    port, server = Sockets.listenany(Sockets.localhost, 8100)
    entry = _write_attach_entry(port, root)
    handle = AttachServer(Int(port), root, server, entry, nothing)
    handle.task = Threads.@spawn begin
        try
            while isopen(server)
                socket = Sockets.accept(server)
                # One task per host connection so a session can serve several
                # notebooks, and several runners, at once. Handshake happens
                # immediately; renders serialize on `_RENDER_LOCK`.
                Threads.@spawn _serve_attached(socket)
            end
        catch err
            if !(err isa Base.IOError || err isa EOFError)
                Logging.@error "Attach server error" exception = (err, catch_backtrace())
            end
        finally
            rm(entry; force = true)
        end
    end
    atexit(() -> rm(entry; force = true))
    return handle
end

# Serve one attached connection, isolating its failures from the accept loop
# and its sibling connections.
function _serve_attached(socket::Sockets.TCPSocket)
    try
        serve_connection(socket)
    catch err
        if !(err isa Base.IOError || err isa EOFError)
            Logging.@error "Attach connection error" exception = (err, catch_backtrace())
        end
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
