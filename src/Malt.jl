"""
The Malt module doesn't export anything, use qualified names instead.
Internal functions are marked with a leading underscore,
these functions are not stable.
"""
module Malt

import BSON
import Pkg
import TOML
using Sockets: Sockets

using RelocatableFolders: RelocatableFolders

include("QuartoNotebookWorker/src/shared.jl")

abstract type AbstractWorker end

"""
Malt will raise a `TerminatedWorkerException` when a `remote_call` is made to a `Worker`
that has already been terminated.
"""
struct TerminatedWorkerException <: Exception end

struct RemoteException <: Exception
    worker::AbstractWorker
    message::String
end

function Base.showerror(io::IO, e::RemoteException)
    print(io, "Remote exception from $(summary(e.worker)):\n\n$(e.message)")
end

struct WorkerResult
    msg_type::UInt8
    value::Any
end

function unwrap_worker_result(worker::AbstractWorker, result::WorkerResult)
    if result.msg_type == MsgType.special_serialization_failure
        throw(
            ErrorException(
                "Error deserializing data from $(summary(worker)):\n\n$(sprint(Base.showerror, result.value))",
            ),
        )
    elseif result.msg_type == MsgType.special_worker_terminated
        throw(TerminatedWorkerException())
    elseif result.msg_type == MsgType.from_worker_call_failure
        throw(RemoteException(worker, result.value))
    else
        result.value
    end
end

const __iNtErNaL_running_procs = Set{Base.Process}()
__iNtErNaL_get_running_procs() = filter!(Base.process_running, __iNtErNaL_running_procs)

"""
    Malt.Worker()

Create a new `Worker`. A `Worker` struct is a handle to a (separate) Julia process.

# Examples

```julia-repl
julia> w = Malt.Worker()
Malt.Worker(0x0000, Process(`…`, ProcessRunning))
```
"""
mutable struct Worker <: AbstractWorker
    port::UInt16
    proc::Base.Process
    proc_pid::Int32

    current_socket::Sockets.TCPSocket
    # socket_lock::ReentrantLock

    current_message_id::MsgID
    expected_replies::Dict{MsgID,Channel{WorkerResult}}

    function Worker(; exe = Base.julia_cmd()[1], env = String[], exeflags = [])
        proc, port, manifest_error = mktempdir() do temp_dir
            # The `errors.log` file is used by the worker process to pass back
            # any errors that occur during startup. This is used instead of
            # capturing the process's `stderr` via a pipe since we only need to
            # be capturing errors like this during initial start up, others
            # that occur once the socket connection is up can just be passed
            # back via the socket.
            errors_log_file = joinpath(temp_dir, "errors.log")
            touch(errors_log_file)

            # The `metadata.toml` file contains worker process metadata that is
            # simpler to compute directly in the worker process once it has
            # started rather than trying to infer from outside of it. Currently
            # the active `Manifest.toml` file and the `VERSION` are stored.
            metadata_toml_file = joinpath(temp_dir, "metadata.toml")
            touch(metadata_toml_file)

            env = vcat("MALT_WORKER_TEMP_DIR=$temp_dir", env)

            # Spawn process
            cmd = _get_worker_cmd(; exe, env, exeflags)
            proc = open(Cmd(cmd; detach = true, windows_hide = true), "w+")

            # Keep internal list
            __iNtErNaL_get_running_procs()
            push!(__iNtErNaL_running_procs, proc)

            # Block until reading the port number of the process (from its stdout)
            port_str = readline(proc)
            port = tryparse(UInt16, port_str)

            # Generate an error message for Julia version mismatches. This does
            # not throw, it just creates the formatted message. We check after
            # the worker is connected to the socket and if there is a mismatch
            # we call `stop` to gracefully close the worker. We cannot
            # gracefully close it until that point.
            manifest_error =
                _validate_worker_process_manifest(metadata_toml_file, errors_log_file)

            if port === nothing
                Base.kill(proc, Base.SIGTERM)

                # First we check whether the command that we tried to start the
                # worker with would actually work. This throws if it doesn't.
                _validate_worker_cmd(exe, exeflags)

                err_output = read(errors_log_file, String)
                if isnothing(manifest_error)
                    # Generic error reporting when we've not received a port
                    # number from the worker. This just prints out the error
                    # message and stacktrace that have come from the worker
                    # process.
                    message = """
                    Failed to start worker process. Expected to read port from stdout, got "$port_str" instead.

                    ERROR: $err_output
                    """
                    error(message)
                else
                    # If we have the manifest error message then we'll print
                    # that one out instead of the generic one since it may be
                    # relevant to the user. It includes the `err_output` as
                    # well, so nothing is lost.
                    error(manifest_error)
                end
            end

            return proc, port, manifest_error
        end

        # Connect
        socket = Sockets.connect(port)
        _buffer_writes(socket)


        # There's no reason to keep the worker process alive after the manager loses its handle.
        w = finalizer(
            w -> @async(stop(w)),
            new(
                port,
                proc,
                getpid(proc),
                socket,
                MsgID(0),
                Dict{MsgID,Channel{WorkerResult}}(),
            ),
        )
        atexit(() -> stop(w))

        _exit_loop(w)
        _receive_loop(w)

        # Only now can we safely check this error and stop the worker if there
        # is a mismatch. Prior to this the `_exit_loop` is not running so a
        # shutdown would not be graceful.
        if !isnothing(manifest_error)
            stop(w)
            error(manifest_error)
        end

        return w
    end
end

# Check that the worker process uses the same version of Julia as is declared
# in the manifest file for the environment that it is trying to use.
#
# If these mismatches aren't checked for explicitly it can result in weird
# stacktraces and generic error messages that don't guide the user to find a
# suitable solution.
#
# This just formats an error message, it does not actually throw the error,
# since that is the responsibility of the caller.
function _validate_worker_process_manifest(
    metadata_toml_file::String,
    error_logs_file::String,
)
    metadata = TOML.parsefile(metadata_toml_file)
    manifest_toml_file = get(metadata, "manifest", "")
    actual_julia_version = get(metadata, "julia_version", "")

    # When there is no manifest file yet then we don't need to report any
    # issues since there will be no resolver issues.
    isfile(manifest_toml_file) || return nothing

    manifest = TOML.parsefile(manifest_toml_file)
    expected_julia_version = get(manifest, "julia_version", "")

    # The older manifest format does not include the `julia_version`. For these
    # ones, just skip the check. To revisit if we encounter issues with this.
    isempty(expected_julia_version) && return nothing

    if actual_julia_version != expected_julia_version
        message = """
        Julia version mismatch in notebook file, see details below.

        manifest = $(repr(manifest_toml_file))
        expected_julia_version = $(repr(expected_julia_version))
        actual_julia_version = $(repr(actual_julia_version))

        Either start the notebook with the correct Julia version using a `juliaup`
        channel specifier in your notebook's frontmatter `julia.exeflags` key, or
        re-resolve the manifest file with `Pkg.resolve()` using the expected Julia
        version before running the notebook.
        """

        error_output = read(error_logs_file, String)
        if !isempty(error_output)
            message *= "\nERROR: $error_output"
        end

        return message
    end

    # Versions before Julia 1.8 do not have access to this function, so we skip
    # the check for them.
    @static if isdefined(Pkg.Operations, :is_manifest_current)
        project_toml_file = get(metadata, "project", "")
        if isfile(project_toml_file)
            env_cache = Pkg.Types.EnvCache(project_toml_file)
            if Pkg.Operations.is_manifest_current(env_cache) === false
                message = """
                The notebook environment is out-of-sync.

                project_toml = $(repr(project_toml_file))
                manifest_toml = $(repr(manifest_toml_file))

                Run `Pkg.resolve()` for this environment to ensure the manifest file
                is consistent with the project file and then rerun this notebook.
                """
            end
        end
    end
end

Base.summary(io::IO, w::Worker) =
    write(io, "Malt.Worker on port $(w.port) with PID $(w.proc_pid)")

function _exit_loop(worker::Worker)
    @async for _i in Iterators.countfrom(1)
        try
            if !isrunning(worker)
                # the worker got shut down, which means that we will never receive one of the expected_replies. So let's give all of them a special_worker_terminated reply.
                for c in values(worker.expected_replies)
                    isready(c) ||
                        put!(c, WorkerResult(MsgType.special_worker_terminated, nothing))
                end
                break
            end
            sleep(1)
        catch e
            @error "Unexpection error inside the exit loop" worker exception =
                (e, catch_backtrace())
        end
    end
end

function _receive_loop(worker::Worker)
    io = worker.current_socket

    # Here we use:
    # `for _i in Iterators.countfrom(1)`
    # instead of
    # `while true`
    # as a workaround for https://github.com/JuliaLang/julia/issues/37154
    @async for _i in Iterators.countfrom(1)
        try
            if !isopen(io)
                @debug("HOST: io closed.")
                break
            end

            @debug "HOST: Waiting for message"
            msg_type = try
                if eof(io)
                    @debug("HOST: io closed.")
                    break
                end
                read(io, UInt8)
            catch e
                if e isa InterruptException
                    @debug(
                        "HOST: Caught interrupt while waiting for incoming data, rethrowing to REPL..."
                    )
                    _rethrow_to_repl(e; rethrow_regular = false)
                    continue # and go back to waiting for incoming data
                else
                    @debug(
                        "HOST: Caught exception while waiting for incoming data, breaking",
                        exception = (e, backtrace())
                    )
                    break
                end
            end
            # this next line can't fail
            msg_id = read(io, MsgID)

            msg_data, success = try
                _bson_deserialize(io), true
            catch err
                err, false
            finally
                _discard_until_boundary(io)
            end

            if !success
                msg_type = MsgType.special_serialization_failure
            end

            # msg_type will be one of:
            #  MsgType.from_worker_call_result
            #  MsgType.from_worker_call_failure
            #  MsgType.special_serialization_failure

            c = get(worker.expected_replies, msg_id, nothing)
            if c isa Channel{WorkerResult}
                put!(c, WorkerResult(msg_type, msg_data))
            else
                @error "HOST: Received a response, but I didn't ask for anything" msg_type msg_id msg_data
            end

            @debug("HOST: Received message", msg_data)
        catch e
            if e isa InterruptException
                @debug "HOST: Interrupted during receive loop."
                _rethrow_to_repl(e)
            elseif e isa Base.IOError && !isopen(io)
                sleep(3)
                if isrunning(worker)
                    @error "HOST: Connection lost with worker, but the process is still running. Killing process..." exception =
                        (e, catch_backtrace())
                    kill(worker, Base.SIGKILL)
                else
                    # This is a clean exit
                end
                break
            else
                @error "HOST: Unknown error" exception = (e, catch_backtrace()) isopen(io)

                break
            end
        end
    end
end

# The entire `src` dir should be relocatable, so that worker.jl can include("MsgType.jl").
const startup_file = RelocatableFolders.@path joinpath(@__DIR__, "startup.jl")
const worker_package = RelocatableFolders.@path joinpath(@__DIR__, "QuartoNotebookWorker")

function _get_worker_cmd(; exe, env, exeflags)
    defaults = Dict(
        "OPENBLAS_NUM_THREADS" => "1",
        "QUARTONOTEBOOKWORKER_PACKAGE" => String(worker_package),
    )
    env = vcat(Base.byteenv(defaults), Base.byteenv(env))
    return addenv(`$exe --startup-file=no $exeflags $(String(startup_file))`, env)
end

# Checks whether a `julia` command (including it's program flags and juliaup
# channel) are runnable. Throws an error when not runnable.
function _validate_worker_cmd(exe, exeflags)
    cmd = `$exe --startup-file=no $exeflags`
    stdout, stderr = IOBuffer(), IOBuffer()
    # When `--version` is appended to the end of any `julia` command it
    # overrides all other flags and just returns the version number so that we
    # don't actually start a Julia process. But it does validate all the flags
    # so we can report problems to the user related to bad flags, or unknown
    # `juliaup` channels.
    if success(pipeline(`$cmd --version`; stdout, stderr))
        version = String(take!(stdout))
        if startswith(version, "julia version")
            return nothing
        else
            # Ideally this never gets hit, but if it does we at least ask the
            # user to report the bug so we can resolve it.
            error(
                "Failed to collect Julia version even though `julia --version` ran successfully. Please report this bug.",
            )
        end
    else
        # This drops all the included environment variables from the error
        # printout below. If left in they swamp the output and make it hard to
        # tell where the exeflags are.
        exe_no_env = setenv(cmd, nothing)
        cmd_error = rstrip(String(take!(stderr)))
        error("""
              Failed to run Julia worker process with the provided command:

              $(exe_no_env)

              The error produced by trying to run this command is shown below:

              $(cmd_error)
              """)
    end
end

## We use tuples instead of structs for messaging so the worker doesn't need to load additional modules.

_new_call_msg(send_result::Bool, f::Function, args, kwargs) =
    (f, args, NamedTuple(kwargs), !send_result)

_new_do_msg(f::Function, args, kwargs) = (f, args, NamedTuple(kwargs), true)

# GENERIC COMMUNICATION PROTOCOL

"""
Low-level: send a message to a worker. Returns a `msg_id::UInt16`, which can be used to wait for a response with `_wait_for_response`.
"""
function _send_msg(
    worker::Worker,
    msg_type::UInt8,
    msg_data,
    expect_reply::Bool = true,
)::MsgID
    _assert_is_running(worker)

    msg_id = (worker.current_message_id += MsgID(1))::MsgID
    if expect_reply
        worker.expected_replies[msg_id] = Channel{WorkerResult}(1)
    end

    @debug("HOST: sending message", msg_data)

    _serialize_msg(worker.current_socket, msg_type, msg_id, msg_data)

    return msg_id
end

"""
Low-level: wait for a response to a previously sent message. Returns the response. Blocking call.
"""
function _wait_for_response(worker::Worker, msg_id::MsgID)
    if haskey(worker.expected_replies, msg_id)
        c = worker.expected_replies[msg_id]
        @debug("HOST: waiting for response of", msg_id)
        response = take!(c)
        delete!(worker.expected_replies, msg_id)
        return unwrap_worker_result(worker, response)
    else
        error("HOST: No response expected for message id $msg_id")
    end
end

"""
`_wait_for_response ∘ _send_msg`
"""
function _send_receive(w::Worker, msg_type::UInt8, msg_data)
    msg_id = _send_msg(w, msg_type, msg_data, true)
    return _wait_for_response(w, msg_id)
end

"""
`@async(_wait_for_response) ∘ _send_msg`
"""
function _send_receive_async(
    w::Worker,
    msg_type::UInt8,
    msg_data,
    output_transformation = identity,
)::Task
    # TODO: Unwrap TaskFailedExceptions
    msg_id = _send_msg(w, msg_type, msg_data, true)
    return @async output_transformation(_wait_for_response(w, msg_id))
end

"""
    Malt.remote_call(f, w::Worker, args...; kwargs...)

Evaluate `f(args...; kwargs...)` in worker `w` asynchronously.
Returns a task that acts as a promise; the result value of the task is the
result of the computation.

The function `f` must already be defined in the namespace of `w`.

# Examples

```julia-repl
julia> promise = Malt.remote_call(uppercase ∘ *, w, "I ", "declare ", "bankruptcy!");

julia> fetch(promise)
"I DECLARE BANKRUPTCY!"
```
"""
function remote_call(f, w::Worker, args...; kwargs...)
    _send_receive_async(
        w,
        MsgType.from_host_call_with_response,
        _new_call_msg(true, f, args, kwargs),
    )
end

"""
    Malt.remote_call_fetch(f, w::Worker, args...; kwargs...)

Shorthand for `fetch(Malt.remote_call(…))`. Blocks and then returns the result of the remote call.
"""
function remote_call_fetch(f, w::AbstractWorker, args...; kwargs...)
    fetch(remote_call(f, w, args...; kwargs...))
end
function remote_call_fetch(f, w::Worker, args...; kwargs...)
    _send_receive(
        w,
        MsgType.from_host_call_with_response,
        _new_call_msg(true, f, args, kwargs),
    )
end

"""
    Malt.remote_call_wait(f, w::Worker, args...; kwargs...)

Shorthand for `wait(Malt.remote_call(…))`. Blocks and discards the resulting value.
"""
function remote_call_wait(f, w::AbstractWorker, args...; kwargs...)
    wait(remote_call(f, w, args...; kwargs...))
end
function remote_call_wait(f, w::Worker, args...; kwargs...)
    _send_receive(
        w,
        MsgType.from_host_call_with_response,
        _new_call_msg(false, f, args, kwargs),
    )
end

"""
    Malt.remote_do(f, w::Worker, args...; kwargs...)

Start evaluating `f(args...; kwargs...)` in worker `w` asynchronously, and return `nothing`.

Unlike `remote_call`, no reference to the remote call is available. This means:
- You cannot wait for the call to complete on the worker.
- The value returned by `f` is not available.
"""
function remote_do(f, w::Worker, args...; kwargs...)
    _send_msg(
        w,
        MsgType.from_host_call_without_response,
        _new_do_msg(f, args, kwargs),
        false,
    )
    nothing
end

## Eval variants

"""
    Malt.remote_eval(mod::Module=Main, w::Worker, expr)

Evaluate expression `expr` under module `mod` on the worker `w`.
`Malt.remote_eval` is asynchronous, like `Malt.remote_call`.

The module `m` and the type of the result of `expr` must be defined in both the
main process and the worker.

# Examples

```julia-repl
julia> Malt.remote_eval(w, quote
    x = "x is a global variable"
end)

julia> Malt.remote_eval_fetch(w, :x)
"x is a global variable"
```

"""
remote_eval(mod::Module, w::AbstractWorker, expr) = remote_call(Core.eval, w, mod, expr)
remote_eval(w::AbstractWorker, expr) = remote_eval(Main, w, expr)

"""
Shorthand for `fetch(Malt.remote_eval(…))`. Blocks and returns the resulting value.
"""
remote_eval_fetch(mod::Module, w::AbstractWorker, expr) =
    remote_call_fetch(Core.eval, w, mod, expr)
remote_eval_fetch(w::AbstractWorker, expr) = remote_eval_fetch(Main, w, expr)

"""
Shorthand for `wait(Malt.remote_eval(…))`. Blocks and discards the resulting value.
"""
remote_eval_wait(mod::Module, w::AbstractWorker, expr) =
    remote_call_wait(Core.eval, w, mod, expr)
remote_eval_wait(w::AbstractWorker, expr) = remote_eval_wait(Main, w, expr)

"""
    Malt.worker_channel(w::AbstractWorker, expr)

Create a channel to communicate with worker `w`. `expr` must be an expression
that evaluates to an `AbstractChannel`. `expr` should assign the channel to a (global) variable
so the worker has a handle that can be used to send messages back to the manager.
"""
function worker_channel(w::Worker, expr)
    RemoteChannel(w, expr)
end

struct RemoteChannel{T} <: AbstractChannel{T}
    worker::Worker
    id::UInt64

    function RemoteChannel{T}(worker::Worker, expr) where {T}

        id = (worker.current_message_id += MsgID(1))::MsgID
        remote_eval_wait(Main, worker, quote
            Main._channel_cache[$id] = $expr
        end)
        new{T}(worker, id)
    end

    RemoteChannel(w::Worker, expr) = RemoteChannel{Any}(w, expr)
end

Base.take!(rc::RemoteChannel) =
    remote_eval_fetch(Main, rc.worker, :(take!(Main._channel_cache[$(rc.id)])))::eltype(rc)

Base.put!(rc::RemoteChannel, v) =
    remote_eval_wait(Main, rc.worker, :(put!(Main._channel_cache[$(rc.id)], $v)))

Base.isready(rc::RemoteChannel) =
    remote_eval_fetch(Main, rc.worker, :(isready(Main._channel_cache[$(rc.id)])))::Bool

Base.wait(rc::RemoteChannel) =
    remote_eval_wait(Main, rc.worker, :(wait(Main._channel_cache[$(rc.id)])))::Bool

## Signals & Termination

"""
    Malt.isrunning(w::Worker)::Bool

Check whether the worker process `w` is running.
"""
isrunning(w::Worker)::Bool = Base.process_running(w.proc)

_assert_is_running(w::Worker) = isrunning(w) || throw(TerminatedWorkerException())

"""
    Malt.stop(w::Worker; exit_timeout::Real=15.0, term_timeout::Real=15.0)::Bool

Terminate the worker process `w` in the nicest possible way. We first try using `Base.exit`, then SIGTERM, then SIGKILL. Waits for the worker process to be terminated.

If `w` is still alive, and now terminated, `stop` returns true.
If `w` is already dead, `stop` returns `false`.
If `w` failed to terminate, throw an exception.
"""
function stop(w::Worker; exit_timeout::Real = 15.0, term_timeout::Real = 15.0)
    ir = () -> !isrunning(w)
    if isrunning(w)
        remote_do(Base.exit, w)
        if !_poll(ir; timeout_s = exit_timeout)
            kill(w, Base.SIGTERM)
            if !_poll(ir; timeout_s = term_timeout)
                kill(w, Base.SIGKILL)
                _wait_for_exit(w)
            end
        end
        true
    else
        false
    end
end

"""
    kill(w::Malt.Worker, signum=Base.SIGTERM)

Terminate the worker process `w` forcefully by sending a `SIGTERM` signal (unless otherwise specified).

This is not the recommended way to terminate the process. See `Malt.stop`.
""" # https://youtu.be/dyIilW_eBjc
Base.kill(w::Worker, signum = Base.SIGTERM) = Base.kill(w.proc, signum)

function _poll(f::Function; interval::Real = 0.01, timeout_s::Real = Inf64)
    tstart = time()
    while true
        f() && return true
        if time() - tstart >= timeout_s
            return false
        end
        sleep(interval)
    end
end

_wait_for_exit(::AbstractWorker; timeout_s::Real = 20.0) = nothing
function _wait_for_exit(w::Worker; timeout_s::Real = 20.0)
    if !_poll(() -> !isrunning(w); timeout_s)
        error("HOST: Worker did not exit after $timeout_s seconds")
    end
end

"""
    Malt.interrupt(w::Worker)

Send an interrupt signal to the worker process. This will interrupt the
latest request (`remote_call*` or `remote_eval*`) that was sent to the worker.
"""
function interrupt(w::Worker)
    if !isrunning(w)
        @warn "Tried to interrupt a worker that has already shut down." summary(w)
    else
        if Sys.iswindows()
            ccall(
                (:GenerateConsoleCtrlEvent, "Kernel32"),
                Bool,
                (UInt32, UInt32),
                UInt32(1),
                UInt32(getpid(w.proc)),
            )
        else
            Base.kill(w.proc, Base.SIGINT)
        end
    end
    nothing
end

# Based on `Base.task_done_hook`
function _rethrow_to_repl(e::InterruptException; rethrow_regular::Bool = false)
    if isdefined(Base, :active_repl_backend) &&
       isdefined(Base.active_repl_backend, :backend_task) &&
       isdefined(Base.active_repl_backend, :in_eval) &&
       Base.active_repl_backend.backend_task.state === :runnable &&
       (isdefined(Base, :Workqueue) || isempty(Base.Workqueue)) &&
       Base.active_repl_backend.in_eval

        @debug "HOST: Rethrowing interrupt to REPL"
        @async Base.schedule(Base.active_repl_backend.backend_task, e; error = true)
    elseif rethrow_regular
        @debug "HOST: Don't know what to do with this interrupt, rethrowing" exception =
            (e, catch_backtrace())
        rethrow(e)
    end
end

end # module
