# Host-side IPC for communicating with worker processes.

module WorkerIPC

import ..QuartoNotebookRunner: UserError

import IOCapture
import Logging
import Pkg
import Sockets
import TOML

import RelocatableFolders

include("QuartoNotebookWorker/src/protocol.jl")

# Exceptions

struct TerminatedWorkerException <: Exception end

struct RemoteException <: Exception
    worker_summary::String
    message::String
end

function Base.showerror(io::IO, e::RemoteException)
    print(io, "Remote exception from $(e.worker_summary):\n\n$(e.message)")
end

# Connection state with locking

mutable struct ConnectionState
    lock::ReentrantLock
    next_id::MsgID
    pending::Dict{MsgID,Channel{Any}}
    closed::Bool

    ConnectionState() = new(ReentrantLock(), MsgID(0), Dict{MsgID,Channel{Any}}(), false)
end

# Worker struct

const _running_procs = Set{Base.Process}()
_get_running_procs() = filter!(Base.process_running, _running_procs)

mutable struct Worker
    port::UInt16
    proc::Base.Process
    proc_pid::Int32
    socket::LockableIO{Sockets.TCPSocket}
    state::ConnectionState
    manifest_file::String

    function Worker(; exe = Base.julia_cmd()[1], env = String[], exeflags = [])
        proc, port, manifest_error, manifest_file = mktempdir() do temp_dir
            errors_log_file = joinpath(temp_dir, "errors.log")
            touch(errors_log_file)

            metadata_toml_file = joinpath(temp_dir, "metadata.toml")
            touch(metadata_toml_file)

            env = vcat("WORKERIPC_TEMP_DIR=$temp_dir", env)

            cmd = _get_worker_cmd(; exe, env, exeflags)
            proc = open(Cmd(cmd; detach = true, windows_hide = true), "w+")

            _get_running_procs()
            push!(_running_procs, proc)

            port_str = readline(proc)
            port = tryparse(UInt16, port_str)

            manifest_file, manifest_error =
                _validate_worker_process_manifest(metadata_toml_file, errors_log_file)

            if port === nothing
                Base.kill(proc, Base.SIGTERM)
                _validate_worker_cmd(exe, exeflags)

                err_output = read(errors_log_file, String)
                if isnothing(manifest_error)
                    empty_result = IOCapture.capture(; rethrow = InterruptException) do
                        run(_get_worker_cmd(; exe, env, exeflags, file = String(empty_file)))
                    end
                    if empty_result.error
                        error("Failed to start worker process.\n\n$(empty_result.output)")
                    end
                    error(
                        "Failed to start worker process. Expected port, got \"$port_str\".\n\nERROR: $err_output",
                    )
                else
                    throw(UserError(manifest_error))
                end
            end

            return proc, port, manifest_error, manifest_file
        end

        socket = LockableIO(Sockets.connect(port))

        # Read handshake from worker
        read_handshake(socket)

        w = finalizer(
            w -> Threads.@spawn(stop(w)),
            new(port, proc, getpid(proc), socket, ConnectionState(), manifest_file),
        )
        atexit(() -> stop(w))

        _exit_loop(w)
        _receive_loop(w)

        if !isnothing(manifest_error)
            stop(w)
            throw(UserError(manifest_error))
        end

        _manifest_in_sync_check(w)

        return w
    end
end

Base.summary(w::Worker) = "Worker on port $(w.port) with PID $(w.proc_pid)"

# Public API

function call(worker::Worker, request::T)::response_type(T) where {T<:IPCRequest}
    state = worker.state

    msg_id, ch = lock(state.lock) do
        state.closed && throw(TerminatedWorkerException())
        id = (state.next_id += MsgID(1))
        ch = Channel{Any}(1)
        state.pending[id] = ch
        (id, ch)
    end

    try
        payload = _ipc_serialize(request)
        write_message(worker.socket, Message(MsgType.CALL, msg_id, payload))
    catch e
        if e isa Base.IOError
            _mark_closed(worker)
            take!(ch)  # Get error from _mark_closed
            throw(TerminatedWorkerException())
        end
        lock(state.lock) do
            delete!(state.pending, msg_id)
        end
        rethrow()
    end

    result = take!(ch)

    if result isa Tuple{Bool,Any}
        success, value = result
        success || throw(RemoteException(summary(worker), value))
        return value
    else
        # :terminated from _mark_closed or :deserialize_error from _receive_loop
        throw(TerminatedWorkerException())
    end
end

isrunning(w::Worker)::Bool = Base.process_running(w.proc)

function stop(w::Worker; exit_timeout::Real = 15.0, term_timeout::Real = 15.0)
    isrunning(w) || return false

    try
        payload = _ipc_serialize(nothing)
        write_message(w.socket, Message(MsgType.SHUTDOWN, MsgID(0), payload))
    catch
    end

    if !_poll(() -> !isrunning(w); timeout_s = exit_timeout)
        Base.kill(w.proc, Base.SIGTERM)
        if !_poll(() -> !isrunning(w); timeout_s = term_timeout)
            Base.kill(w.proc, Base.SIGKILL)
        end
    end

    _mark_closed(w)
    return true
end

# Internal

function _mark_closed(worker::Worker)
    lock(worker.state.lock) do
        worker.state.closed && return
        worker.state.closed = true
        for ch in values(worker.state.pending)
            isready(ch) || put!(ch, :terminated)
        end
        empty!(worker.state.pending)
    end
end

function _receive_loop(worker::Worker)
    Threads.@spawn begin
        io = worker.socket
        state = worker.state

        while true
            try
                isopen(io.io) || break
                eof(io.io) && break

                msg = read_message(io)

                # Atomically get and remove channel from pending to avoid race with _mark_closed
                ch = lock(state.lock) do
                    ch = get(state.pending, msg.id, nothing)
                    if ch !== nothing
                        delete!(state.pending, msg.id)
                    end
                    ch
                end

                if ch === nothing
                    Logging.@error "HOST: response for unknown msg_id, treating as protocol corruption" msg.id
                    break
                end

                data = try
                    _ipc_deserialize(msg.payload)
                catch e
                    Logging.@error "HOST: deserialize error" exception =
                        (e, catch_backtrace())
                    put!(ch, :deserialize_error)
                    continue
                end

                success = msg.type == MsgType.RESULT_OK
                put!(ch, (success, data))
            catch e
                if e isa InterruptException
                    continue
                elseif e isa EOFError || e isa Base.IOError
                    break
                else
                    Logging.@error "HOST: receive loop error" exception =
                        (e, catch_backtrace())
                    break
                end
            end
        end

        _mark_closed(worker)
    end
end

function _exit_loop(worker::Worker)
    Threads.@spawn begin
        while true
            try
                if !isrunning(worker)
                    _mark_closed(worker)
                    break
                end
                sleep(1)
            catch e
                Logging.@error "HOST: exit loop error" exception = (e, catch_backtrace())
            end
        end
    end
end

function _poll(f::Function; interval::Real = 0.01, timeout_s::Real = Inf64)
    tstart = time()
    while true
        f() && return true
        time() - tstart >= timeout_s && return false
        sleep(interval)
    end
end

# Worker process startup

const startup_file = RelocatableFolders.@path joinpath(@__DIR__, "startup.jl")
const empty_file = RelocatableFolders.@path joinpath(@__DIR__, "empty.jl")
const worker_package = RelocatableFolders.@path joinpath(@__DIR__, "QuartoNotebookWorker")

function _get_worker_cmd(; exe, env, exeflags, file = String(startup_file))
    defaults = Dict(
        "OPENBLAS_NUM_THREADS" => "1",
        "QUARTONOTEBOOKWORKER_PACKAGE" => String(worker_package),
    )
    env = vcat(Base.byteenv(defaults), Base.byteenv(env))
    return addenv(`$exe --startup-file=no $exeflags $file`, env)
end

function _validate_worker_cmd(exe, exeflags)
    cmd = `$exe --startup-file=no $exeflags`
    stdout_buf, stderr_buf = IOBuffer(), IOBuffer()
    if success(pipeline(`$cmd --version`; stdout = stdout_buf, stderr = stderr_buf))
        version = String(take!(stdout_buf))
        if startswith(version, "julia version")
            return nothing
        else
            error("Failed to collect Julia version. Please report this bug.")
        end
    else
        exe_no_env = setenv(cmd, nothing)
        cmd_error = rstrip(String(take!(stderr_buf)))
        throw(
            UserError(
                "Failed to run Julia worker with command:\n\n$exe_no_env\n\n$cmd_error",
            ),
        )
    end
end

function _validate_worker_process_manifest(
    metadata_toml_file::String,
    error_logs_file::String,
)
    metadata = TOML.parsefile(metadata_toml_file)
    manifest_toml_file = get(metadata, "manifest", "")
    actual_julia_version = get(metadata, "julia_version", "")

    isfile(manifest_toml_file) || return "", nothing

    manifest = TOML.parsefile(manifest_toml_file)
    expected_julia_version = get(manifest, "julia_version", "")
    project_hash = get(manifest, "project_hash", "")

    isempty(expected_julia_version) && return project_hash, nothing

    if !_compare_versions(actual_julia_version, expected_julia_version)
        message = """
        Julia version mismatch in notebook file.

        manifest = $(repr(manifest_toml_file))
        expected_julia_version = $(repr(expected_julia_version))
        actual_julia_version = $(repr(actual_julia_version))

        Either start the notebook with the correct Julia version using a `juliaup`
        channel specifier in your notebook's frontmatter `julia.exeflags` key, or
        re-resolve the manifest file with `Pkg.resolve()`.
        """

        error_output = read(error_logs_file, String)
        isempty(error_output) || (message *= "\nERROR: $error_output")

        return project_hash, message
    end
    return project_hash, nothing
end

_compare_versions(a::AbstractString, b::AbstractString) =
    _compare_versions(tryparse(VersionNumber, a), tryparse(VersionNumber, b))
_compare_versions(a::VersionNumber, b::VersionNumber) =
    a.major == b.major && a.minor == b.minor && a.patch == b.patch
_compare_versions(_, _) = false

function _manifest_in_sync_check(w::Worker)
    msg = call(w, ManifestInSyncRequest())
    if !isnothing(msg)
        stop(w)
        throw(UserError(msg))
    end
end

end # module
