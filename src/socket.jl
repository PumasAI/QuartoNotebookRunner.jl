# TCP socket server for running Quarto notebooks from external processes.

struct SocketServer
    tcpserver::Sockets.TCPServer
    notebookserver::Server
    port::Int
    task::Task
end

Base.wait(s::SocketServer) = wait(s.task)

"""
    serve(; port = nothing, showprogress::Bool = true, timeout::Union{Nothing,Real} = nothing)

Start a socket server for running Quarto notebooks from external processes.
Call `wait(server)` on the returned server to block until the server is closed.

The port can be specified as `nothing`, an integer or string. If it's `nothing`,
a random port will be chosen.

When `timeout` is not `nothing`, a timer is setup which closes the server after
`timeout` seconds of inactivity. The timer is halted when a message arrives and
reset after the last active command has been processed fully (so the server will not time
out while rendering a long-running notebook, for example).

Message schema:

```json
{
    type: "run" | "close" | "stop" | "isopen" | "isready"
    content: string | { file: string, options: string | { ... } }
}
```

A description of the message types:

 -  `run` - Run a notebook. The content should be the absolute path to the
    notebook file. When the notebook is run, the server will return a response
    with the entire evaluated notebook content in a `notebook` field. Reuse a
    notebook process on subsequent runs. To restart a notebook, close it and run
    it again.

 -  `close` - Close a notebook. The `content` should be the absolute path to
    the notebook file. If no file is specified, all notebooks will be closed.
    When the notebook is closed, the server will return a response with a
    `status` field set to `true`.

 -  `stop` - Stop the server. The server will return a response with a `message`
    field set to `Server stopped.`.

 -  `isopen` - Check if a notebook specified by the absolute path in `content`
    has already been `run` and therefore has a worker open in the background.
    If so return `true` else `false`. If `true` then you should be able to call
    `close` for that file without an error.

 -  `isready` - Returns `true` if the server is ready to accept commands. Should
    never return `false`.
"""
function serve(;
    port = nothing,
    showprogress::Bool = true,
    timeout::Union{Nothing,Real} = nothing,
)
    getport(port::Integer) = port
    getport(port::AbstractString) = getport(tryparse(Int, port))
    getport(port::Nothing) = port
    getport(::Any) = throw(ArgumentError("Invalid port: $port"))

    timeout !== nothing &&
        timeout < 0 &&
        throw(ArgumentError("Non-negative timeout value $timeout"))

    port = getport(port)
    @debug "Starting notebook server." port

    notebook_server = Server()
    closed_deliberately = Ref(false)

    if port === nothing
        port, socket_server = Sockets.listenany(8000)
    else
        socket_server = Sockets.listen(port)
    end

    timer_lock = ReentrantLock()
    timer_refcount = Ref(1)
    timer = Ref{Union{Timer,Nothing}}(nothing)

    resume_timeout_if_idle!() =
        lock(timer_lock) do
            timeout === nothing && return

            # only continue if all but one calls to `suspend_timeout!` had their corresponding
            # `resume_timeout_if_idle!` called already, which means that now no other
            # command is active and we can close down
            timer_refcount[] -= 1
            timer_refcount[] == 0 || return

            if timer[] !== nothing
                close(timer[])
            end
            timer[] = Timer(timeout) do _
                @debug "Server timed out after $timeout seconds of inactivity."
                # close(socket_server) will cause an exception on the
                # Sockets.accept line so we use this flag to swallow the
                # error if that happened on purpose
                closed_deliberately[] = true
                close!(notebook_server)
                close(socket_server)
            end
        end
    suspend_timeout!() =
        lock(timer_lock) do
            timeout === nothing && return

            timer_refcount[] += 1
            if timer[] !== nothing
                close(timer[])
            end
            timer[] = nothing
        end

    resume_timeout_if_idle!()

    task = Threads.@spawn begin
        while isopen(socket_server)
            socket = nothing
            try
                socket = Sockets.accept(socket_server)
            catch error
                if !closed_deliberately[]
                    @error "Failed to accept connection" error
                end
                break
            end
            if !isnothing(socket)
                Threads.@spawn while isopen(socket)
                    @debug "Waiting for request"
                    data = readline(socket; keep = true)
                    if isempty(data)
                        @debug "Connection closed."
                        break
                    else
                        suspend_timeout!()

                        json = try
                            _read_json(data)
                        catch error
                            msg = "Failed to parse json message."
                            @error msg error
                            _write_json(socket, (; error = msg))
                            continue
                        end
                        @debug "Received request" json
                        if json.type == "stop"
                            @debug "Closing connection."
                            close!(notebook_server)
                            _write_json(socket, (; message = "Server stopped."))
                            close(socket)
                            # close(socket_server) will cause an exception on the
                            # Sockets.accept line so we use this flag to swallow the
                            # error if that happened on purpose
                            closed_deliberately[] = true
                            close(socket_server)
                        elseif json.type == "isready"
                            _write_json(socket, true)
                        else
                            _write_json(
                                socket,
                                _handle_response(notebook_server, json, showprogress),
                            )
                        end

                        # when a message has been processed completely, start timer
                        # if no other command is currently running
                        resume_timeout_if_idle!()
                    end
                end
            end
        end
        @debug "Server closed."
    end

    errormonitor(task)

    return SocketServer(socket_server, notebook_server, port, task)
end

function _handle_response(
    notebooks::Server,
    request::@NamedTuple{type::String, content::Union{String,Dict{String,Any}}},
    showprogress::Bool,
)
    @debug "debugging" request notebooks = collect(keys(notebooks.workers))
    type = request.type

    type in ("close", "run", "isopen") || return _log_error("Unknown request type: $type")

    file = _get_file(request.content)

    # Closing:

    if type == "close" && isempty(file)
        close!(notebooks)
        return (; message = "Notebooks closed.")
    end

    isabspath(file) || return _log_error("File path must be absolute: $(repr(file))")
    isfile(file) || return _log_error("File does not exist: $(repr(file))")

    if type == "close"
        try
            close!(notebooks, file)
            return (; status = true)
        catch error
            return _log_error("Failed to close notebook: $file", error, catch_backtrace())
        end
    end

    # Running:

    if type == "run"
        options = _get_options(request.content)
        try
            return (; notebook = run!(notebooks, file; options, showprogress))
        catch error
            return _log_error("Failed to run notebook: $file", error, catch_backtrace())
        end
    end

    if type == "isopen"
        return haskey(notebooks.workers, file)
    end

    # Shouldn't get to this point.
    error("unreachable reached.")
end

function _log_error(message, error, backtrace)
    @error message exception = (error, backtrace)
    return (; error = message, juliaError = sprint(Base.showerror, error, backtrace))
end
function _log_error(message)
    @error message
    return (; error = message, juliaError = sprint(Base.showerror, error, backtrace))
end

# TODO: check what the message schema is for this.
_read_json(data) = JSON3.read(
    data,
    @NamedTuple{type::String, content::Union{String,Union{String,Dict{String,Any}}}}
)
_write_json(socket, data) = write(socket, JSON3.write(data), "\n")

function _get_file(content::Dict)
    if haskey(content, "file")
        return content["file"]
    else
        error("No 'file' key in content: $(repr(content))")
    end
end
_get_file(content::String) = content

_get_options(content::Dict) = get(Dict{String,Any}, content, "options")
_get_options(::String) = Dict{String,Any}()

# Compat:

if !isdefined(Base, :errormonitor)
    function errormonitor(t::Task)
        t2 = Task() do
            if istaskfailed(t)
                local errs = stderr
                try # try to display the failure atomically
                    errio = IOContext(PipeBuffer(), errs::IO)
                    Base.emphasize(errio, "Unhandled Task ")
                    Base.display_error(errio, Base.catch_stack(t))
                    write(errs, errio)
                catch
                    try # try to display the secondary error atomically
                        errio = IOContext(PipeBuffer(), errs::IO)
                        print(
                            errio,
                            "\nSYSTEM: caught exception while trying to print a failed Task notice: ",
                        )
                        Base.display_error(errio, Base.catch_stack())
                        write(errs, errio)
                        flush(errs)
                        # and then the actual error, as best we can
                        Core.print(Core.stderr, "while handling: ")
                        Core.println(Core.stderr, Base.catch_stack(t)[end][1])
                    catch e
                        # give up
                        Core.print(
                            Core.stderr,
                            "\nSYSTEM: caught exception of type ",
                            typeof(e).name.name,
                            " while trying to print a failed Task notice; giving up\n",
                        )
                    end
                end
            end
            nothing
        end
        Base._wait2(t, t2)
        return t
    end
end
