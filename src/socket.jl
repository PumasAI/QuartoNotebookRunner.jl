# TCP socket server for running Quarto notebooks from external processes.

struct SocketServer
    tcpserver::Sockets.TCPServer
    notebookserver::Server
    port::Int
    task::Task
    key::Base.UUID
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

Messages are composed of a payload string which needs to be valid JSON, and
need to be signed with the base64 encoded HMAC256 digest of this JSON string,
using the UUID `server.key` as the key. Upon receiving a message, the server
will verify that `hmac == base64(hmac256(payload, key))` before processing it
further.

```json
{
    hmac: string,
    payload: string
}
```

The JSON-decoded `payload` string gives the actual server command and
should match the following schema:

```json
{
    type: "run" | "close" | "stop" | "isopen" | "isready"
    content: string | { file: string, options: string | { ... } }
}
```

A description of the message types:

 -  `run` - Run a notebook. The content should be the absolute path to the
    notebook file.
    For each chunk that is evaluated, the server will return an object with schema
    `{type: "progress_update", chunkIndex: number, nChunks: number, source: string, line: number}`
    before the respective chunk is evaluated.
    After the processing has finished, the server will return a response
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

    key = Base.UUID(rand(UInt128))

    notebook_server = Server()
    closed_deliberately = Ref(false)

    if port === nothing
        port, socket_server = Sockets.listenany(8000)
    else
        socket_server = Sockets.listen(port)
    end

    timer = Ref{Union{Timer,Nothing}}(nothing)

    function set_timer!()
        @debug "Timer set up"
        timer[] = Timer(timeout) do _
            @debug "Server timed out after $timeout seconds of inactivity."
            # close(socket_server) will cause an exception on the
            # Sockets.accept line so we use this flag to swallow the
            # error if that happened on purpose
            lock(notebook_server.lock) do
                if !isempty(notebook_server.workers)
                    @debug "Timeout fired but workers were not empty at attaining server lock, not shutting down server."
                    return
                end
                closed_deliberately[] = true
                close!(notebook_server)
                close(socket_server)
            end
        end
    end

    # this function is called under server.lock so we don't need further synchronization
    notebook_server.on_change[] =
        n_workers::Int -> begin
            timeout === nothing && return

            if n_workers == 0
                if timer[] !== nothing
                    error(
                        "Timer was already set even though the number of workers just changed to zero. This must be a bug.",
                    )
                end
                set_timer!()
            else
                if timer[] !== nothing
                    @debug "Closing active timer"
                    close(timer[])
                    timer[] = nothing
                end
            end
            return
        end

    timeout !== nothing && set_timer!()

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
                        json = try
                            _read_json(key, data)
                        catch error
                            msg = if error isa HMACMismatchError
                                "Incorrect HMAC digest"
                            else
                                "Failed to parse json message."
                            end
                            @error msg error
                            _write_json(socket, (; error = msg))
                            # close connection with clients sending wrong hmacs or invalid json
                            # (could be other processes mistakingly targeting our port)
                            close(socket)
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
                            _handle_response(socket, notebook_server, json, showprogress)
                        end
                    end
                end
            end
        end
        @debug "Server closed."
    end

    errormonitor(task)

    return SocketServer(socket_server, notebook_server, port, task, key)
end

function _handle_response(
    socket,
    notebooks::Server,
    request::@NamedTuple{type::String, content::Union{String,Dict{String,Any}}},
    showprogress::Bool,
)
    @debug "debugging" request notebooks = collect(keys(notebooks.workers))
    type = request.type

    type in ("close", "run", "isopen") ||
        return _write_json(socket, _log_error("Unknown request type: $type"))

    file = _get_file(request.content)

    # Closing:

    if type == "close" && isempty(file)
        close!(notebooks)
        return (; message = "Notebooks closed.")
    end

    isabspath(file) ||
        return _write_json(socket, _log_error("File path must be absolute: $(repr(file))"))
    isfile(file) ||
        return _write_json(socket, _log_error("File does not exist: $(repr(file))"))

    if type == "close"
        try
            close!(notebooks, file)
            return _write_json(socket, (; status = true))
        catch error
            return _write_json(
                socket,
                _log_error("Failed to close notebook: $file", error, catch_backtrace()),
            )
        end
    end

    # Running:

    if type == "run"
        options = _get_options(request.content)
        markdown = _get_markdown(options)

        function chunk_callback(i, n, chunk)
            _write_json(
                socket,
                (;
                    type = :progress_update,
                    chunkIndex = i,
                    nChunks = n,
                    source = chunk.source,
                    line = chunk.line,
                ),
            )
        end

        result = try
            (; notebook = run!(notebooks, file; options, markdown, showprogress, chunk_callback))
        catch error
            _log_error("Failed to run notebook: $file", error, catch_backtrace())
        end
        return _write_json(socket, result)
    end

    if type == "isopen"
        return _write_json(socket, haskey(notebooks.workers, file))
    end

    # Shouldn't get to this point.
    error("unreachable reached.")
end

function _log_error(message, error, backtrace)
    @error message exception = (error, backtrace)
    return (; error = message, juliaError = sprint(Base.showerror, error, backtrace))
end
# EvaluationErrors don't send their local backtrace because only the contained
# notebook-related errors are interesting for the user
function _log_error(message, error::QuartoNotebookRunner.EvaluationError, backtrace)
    @error message exception = (error, backtrace)
    return (; error = message, juliaError = sprint(Base.showerror, error))
end
function _log_error(message)
    @error message
    return (; error = message)
end

struct HMACMismatchError <: Exception end

# TODO: check what the message schema is for this.
function _read_json(key::Base.UUID, data)
    obj = JSON3.read(data, @NamedTuple{hmac::String, payload::String})
    hmac = obj.hmac
    payload = obj.payload

    hmac_vec_client = Base64.base64decode(hmac)
    hmac_vec_server = SHA.hmac_sha256(Vector{UInt8}(string(key)), payload)
    if !isequal_constant_time(hmac_vec_client, hmac_vec_server)
        throw(HMACMismatchError())
    end

    return JSON3.read(
        payload,
        @NamedTuple{type::String, content::Union{String,Union{String,Dict{String,Any}}}}
    )
end

# https://codahale.com/a-lesson-in-timing-attacks/
@noinline function isequal_constant_time(v1::Vector{UInt8}, v2::Vector{UInt8})
    length(v1) != length(v2) && return false
    result = 0
    for (a, b) in zip(v1, v2)
        result |= a ⊻ b
    end
    return result == 0
end

"""
    _write_hmac_json(socket, key::Base.UUID, data)

Internal utility function to store the json representation of `data` as `payload`,
compute the base64 hmac256 digest from it and then write out the json string `{hmac, payload}`.
"""
function _write_hmac_json(socket, key::Base.UUID, data)
    payload = JSON3.write(data)
    hmac = SHA.hmac_sha256(Vector{UInt8}(string(key)), payload)
    hmac_b64 = Base64.base64encode(hmac)
    write(socket, JSON3.write((; hmac = hmac_b64, payload)), "\n")
end

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

function _get_nested(d::Dict, keys...)
    _d = d
    for key in keys
        _d = get(_d, key, nothing)
        _d === nothing && return
    end
    return _d
end
_get_markdown(options::Dict)::Union{Nothing,String} = _get_nested(options, "target", "markdown", "value")

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
