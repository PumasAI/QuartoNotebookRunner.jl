# Host-side IPC for communicating with worker processes.

module WorkerIPC

import ..QuartoNotebookRunner

import IOCapture
import Logging
import Pkg
import Sockets
import TOML

import RelocatableFolders
import Scratch

include("QuartoNotebookWorker/src/protocol.jl")

# Scratchspace for worker environments, keyed on Project.toml content hash
# so dependency changes invalidate the cached env.
function _get_scratchspace_path()
    worker_project = joinpath(String(worker_package), "Project.toml")
    project_hash = string(hash(read(worker_project)); base = 62)
    key = "worker-qnr$(QuartoNotebookRunner.QNR_VERSION)-$(project_hash)"
    Scratch.@get_scratch!(key)
end

# Exceptions

struct TerminatedWorkerException <: Exception end

struct RemoteException <: Exception
    worker_summary::String
    message::String
end

function Base.showerror(io::IO, e::RemoteException)
    print(io, "Remote exception from $(e.worker_summary):\n\n$(e.message)")
end

# Type-stable result types for pending calls

struct CallOk{T}
    value::T
end

struct CallErr
    exception::Exception
end

const CallResult{T} = Union{CallOk{T},CallErr}

# Pending call with parametric response type for type-stable dispatch

abstract type AbstractPendingCall end

struct PendingCall{R} <: AbstractPendingCall
    channel::Channel{CallResult{R}}
    worker_summary::String
end

function deliver!(p::PendingCall{R}, success::Bool, data) where {R}
    result = if success
        if data isa R
            CallOk{R}(data)
        else
            CallErr(
                RemoteException(
                    p.worker_summary,
                    "Type mismatch: expected $R, got $(typeof(data))",
                ),
            )
        end
    else
        if data isa String
            CallErr(RemoteException(p.worker_summary, data))
        else
            CallErr(
                RemoteException(
                    p.worker_summary,
                    "Unknown error (unexpected type: $(typeof(data)))",
                ),
            )
        end
    end
    put!(p.channel, result)
end

function deliver_failure!(p::AbstractPendingCall)
    put!(p.channel, CallErr(TerminatedWorkerException()))
end

# Connection state with locking

mutable struct ConnectionState
    lock::ReentrantLock
    next_id::MsgID
    pending::Dict{MsgID,AbstractPendingCall}
    closed::Bool

    ConnectionState() =
        new(ReentrantLock(), MsgID(0), Dict{MsgID,AbstractPendingCall}(), false)
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

    function Worker(;
        exe = Base.julia_cmd()[1],
        env = String[],
        exeflags = [],
        strict_manifest_versions = false,
        sandbox_base,
    )
        scratchspace = _get_scratchspace_path()

        proc, port, manifest_error, manifest_file = mktempdir() do temp_dir
            errors_log_file = joinpath(temp_dir, "errors.log")
            touch(errors_log_file)

            metadata_toml_file = joinpath(temp_dir, "metadata.toml")
            touch(metadata_toml_file)

            env = vcat("WORKERIPC_TEMP_DIR=$temp_dir", env)

            cmd = _get_worker_cmd(; exe, env, exeflags, scratchspace, sandbox_base)
            proc = open(Cmd(cmd; detach = true, windows_hide = true), "w+")

            _get_running_procs()
            push!(_running_procs, proc)

            port_str = readline(proc)
            port = tryparse(UInt16, port_str)

            manifest_file, manifest_error = _validate_worker_process_manifest(
                metadata_toml_file,
                errors_log_file;
                strict = strict_manifest_versions,
            )

            if port === nothing
                # Process may already be dead; ignore kill errors (esp. EACCES on Windows)
                try
                    Base.kill(proc, Base.SIGTERM)
                catch err
                    @debug "failed to kill worker process" exception =
                        (err, catch_backtrace())
                end
                _validate_worker_cmd(exe, exeflags)

                err_output = read(errors_log_file, String)
                if isnothing(manifest_error)
                    empty_result = IOCapture.capture(; rethrow = InterruptException) do
                        run(
                            _get_worker_cmd(;
                                exe,
                                env,
                                exeflags,
                                file = String(empty_file),
                                scratchspace,
                                sandbox_base,
                            ),
                        )
                    end
                    if empty_result.error
                        error("Failed to start worker process.\n\n$(empty_result.output)")
                    end
                    error(
                        "Failed to start worker process. Expected port, got \"$port_str\".\n\nERROR: $err_output",
                    )
                else
                    throw(QuartoNotebookRunner.UserError(manifest_error))
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
            throw(QuartoNotebookRunner.UserError(manifest_error))
        end

        _manifest_in_sync_check(w)

        return w
    end
end

Base.summary(w::Worker) = "Worker on port $(w.port) with PID $(w.proc_pid)"

# Public API

function call(worker::Worker, request::T)::response_type(T) where {T<:IPCRequest}
    R = response_type(T)
    state = worker.state
    ch = Channel{CallResult{R}}(1)
    pending_call = PendingCall{R}(ch, summary(worker))

    msg_id = lock(state.lock) do
        state.closed && throw(TerminatedWorkerException())
        id = (state.next_id += MsgID(1))
        state.pending[id] = pending_call
        id
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
    result isa CallOk ? result.value : throw(result.exception)
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
        for p in values(worker.state.pending)
            deliver_failure!(p)
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

                pending_call = lock(state.lock) do
                    pop!(state.pending, msg.id, nothing)
                end

                if pending_call === nothing
                    Logging.@error "HOST: response for unknown msg_id, treating as protocol corruption" msg.id
                    break
                end

                data = try
                    _ipc_deserialize(msg.payload)
                catch e
                    Logging.@error "HOST: deserialize error" exception =
                        (e, catch_backtrace())
                    deliver_failure!(pending_call)
                    continue
                end

                deliver!(pending_call, msg.type == MsgType.RESULT_OK, data)
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

function _get_worker_cmd(;
    exe,
    env,
    exeflags,
    file = String(startup_file),
    scratchspace,
    sandbox_base,
)
    defaults = Dict(
        "OPENBLAS_NUM_THREADS" => "1",
        "QUARTONOTEBOOKWORKER_PACKAGE" => String(worker_package),
        "QUARTONOTEBOOKWORKER_SCRATCHSPACE" => scratchspace,
        "QUARTONOTEBOOKWORKER_SANDBOX_BASE" => sandbox_base,
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
            QuartoNotebookRunner.UserError(
                "Failed to run Julia worker with command:\n\n$exe_no_env\n\n$cmd_error",
            ),
        )
    end
end

function _validate_worker_process_manifest(
    metadata_toml_file::String,
    error_logs_file::String;
    strict::Bool = false,
)
    metadata = TOML.parsefile(metadata_toml_file)
    manifest_toml_file = get(metadata, "manifest", "")
    actual_julia_version = get(metadata, "julia_version", "")

    isfile(manifest_toml_file) || return "", nothing

    manifest = TOML.parsefile(manifest_toml_file)
    expected_julia_version = get(manifest, "julia_version", "")
    project_hash = get(manifest, "project_hash", "")

    isempty(expected_julia_version) && return project_hash, nothing

    if !_compare_versions(actual_julia_version, expected_julia_version; strict)
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

_compare_versions(a::AbstractString, b::AbstractString; strict = false) =
    _compare_versions(tryparse(VersionNumber, a), tryparse(VersionNumber, b); strict)
_compare_versions(a::VersionNumber, b::VersionNumber; strict = false) =
    a.major == b.major && a.minor == b.minor && (strict ? a.patch == b.patch : true)
_compare_versions(::Any, ::Any; strict = false) = false

function _manifest_in_sync_check(w::Worker)
    msg = call(w, ManifestInSyncRequest())
    if !isnothing(msg)
        stop(w)
        throw(QuartoNotebookRunner.UserError(msg))
    end
end

end # module
