# Server lifecycle: run!, borrow_file!, close!, forceclose!, render.
#
# Locking protocol:
#
# server.lock guards mutation/lookup of server.workers and server.shared_workers.
# file.lock guards mutation of a File's state and ensures exclusive evaluation.
#
# Ordering: always acquire server.lock BEFORE file.lock.
# Exception: borrow_file! acquires file.lock outside server.lock for pre-existing
# files, then re-validates under server.lock (staleness check + recursion).
#
# forceclose! intentionally bypasses file.lock by setting force_close_requested
# (atomic) and killing the worker process directly. run! detects forceclose
# when WorkerIPC.call throws TerminatedWorkerException and the flag is set.
# All FileState transitions happen under file.lock.

function run!(
    server::Server,
    path::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    markdown::Union{Nothing,String} = nothing,
    showprogress::Bool = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
    chunk_callback = (i, n, c) -> nothing,
    source_ranges::Union{Nothing,Vector} = nothing,
)
    try
        borrow_file!(server, path; options, optionally_create = true) do file
            transition!(file, FileState.Ready, FileState.Running)
            file.force_close_requested[] = false
            if file.timeout_timer !== nothing
                close(file.timeout_timer)
                file.timeout_timer = nothing
            end
            file.run_started = Dates.now()
            file.run_finished = nothing

            try
                result = evaluate!(
                    file,
                    output;
                    showprogress,
                    options,
                    markdown,
                    chunk_callback,
                    source_ranges,
                )

                # Eval succeeded but worker may have been killed after last IPC call.
                if file.force_close_requested[]
                    transition!(file, FileState.Running, FileState.Closing)
                    error("File was force-closed during run")
                end

                file.run_finished = Dates.now()
                transition!(file, FileState.Running, FileState.Ready)
                if file.timeout > 0
                    file.timeout_timer = Timer(file.timeout) do _
                        close!(server, file.path)
                        @debug "File at $(file.path) timed out after $(file.timeout) seconds of inactivity."
                    end
                else
                    close!(server, file.path)
                end
                return result
            catch err
                # Reset to Ready so file is reusable after eval errors.
                # Skip if forceclose already transitioned to Closing.
                if file.state === FileState.Running
                    if file.force_close_requested[]
                        transition!(file, FileState.Running, FileState.Closing)
                        error("File was force-closed during run")
                    else
                        transition!(file, FileState.Running, FileState.Ready)
                    end
                end
                rethrow(err)
            end
        end
    catch err
        if err isa FileBusyError
            throw(
                UserError(
                    "Tried to run file \"$path\" but the corresponding worker is busy.",
                ),
            )
        else
            rethrow(err)
        end
    end
end

"""
    borrow_file!(f, server, path; wait = false, optionally_create = false, options = Dict{String,Any}())

Executes `f(file)` while the `file`'s `ReentrantLock` is locked.
All actions on a `Server`'s `File` should be wrapped in this
so that no two tasks can mutate the `File` at the same time.
When `optionally_create` is `true`, the `File` will be created on the server
if it doesn't exist, in which case it is passed `options`.
If `wait = false`, `borrow_file!` will throw a `FileBusyError` if the lock cannot be attained immediately.
"""
function borrow_file!(
    f,
    server,
    path;
    wait = false,
    optionally_create = false,
    options = Dict{String,Any}(),
)
    apath = abspath(path)

    prelocked, file = lock(server.lock) do
        if haskey(server.workers, apath)
            return false, server.workers[apath]
        else
            if optionally_create
                # it's not ideal to create the `File` under server.lock but it takes a second or
                # so on my machine to init it, so for practical purposes it should be ok
                file = _create_file(server, apath, options)
                server.workers[apath] = file
                lock(file.lock) # don't let anything get to the fresh file before us
                on_change(server)
                return true, file
            else
                throw(NoFileEntryError(apath))
            end
        end
    end

    if prelocked
        return try
            f(file)
        finally
            unlock(file.lock)
        end
    else
        # we will now try to attain the lock of a previously existing file. once we have attained
        # it though, it could be that the file is stale because it has been
        # removed and possibly reopened in the meantime. So if
        # no file exists or it doesn't match the one we have, we recurse into `borrow_file!`.
        # This could in principle go on forever but is very unlikely to with a small number of
        # concurrent users.

        if wait
            lock(file.lock)
            lock_attained = true
        else
            lock_attained = trylock(file.lock)
        end

        try
            if !lock_attained
                throw(FileBusyError(apath))
            end
            current_file = lock(server.lock) do
                get(server.workers, apath, nothing)
            end
            if file !== current_file
                return borrow_file!(f, server, apath; options, optionally_create)
            else
                return f(file)
            end
        finally
            lock_attained && unlock(file.lock)
        end
    end
end

"""
    render(file::AbstractString; output::Union{AbstractString,IO,Nothing} = nothing, showprogress::Bool = true)

Render the notebook in `file` and write the results to `output`. Uses a similar
API to `run!` but does not keep the file loaded in a server and shuts down
immediately after rendering. This means that the user pays the full cost of
initial startup each time they render a notebook. Prefer `run!` if you are going
to be rendering the same notebook multiple times iteratively.
"""
function render(
    file::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    showprogress::Bool = true,
)
    server = Server()
    run!(server, file; output, showprogress)
    close!(server, file)
end

# Shared worker cleanup helpers.

"""
    _unregister_file!(server, file)

Remove a file from the server registry. For shared workers, decrements the
ref count and stops the worker if this was the last user.
Must be called under server.lock.
"""
function _unregister_file!(server, file)
    delete!(server.workers, file.path)
    if file.worker_key !== nothing
        entry = get(server.shared_workers, file.worker_key, nothing)
        if entry !== nothing
            delete!(entry.users, file.path)
            if isempty(entry.users)
                WorkerIPC.stop(entry.worker)
                delete!(server.shared_workers, file.worker_key)
            end
        end
    end
    _gc_cache_files(joinpath(dirname(file.path), ".cache"))
    on_change(server)
end

"""
    _forceclose_signal_siblings!(server, file, apath)

Signal all sibling files sharing the same worker to forceclose.
Must be called before killing the shared worker so siblings detect
forceclose via the atomic flag rather than a raw TerminatedWorkerException.
"""
function _forceclose_signal_siblings!(server, file, apath)
    lock(server.lock) do
        entry = get(server.shared_workers, file.worker_key, nothing)
        if entry !== nothing
            for sibling_path in entry.users
                sibling_path == apath && continue
                sibling = get(server.workers, sibling_path, nothing)
                if sibling !== nothing
                    sibling.force_close_requested[] = true
                end
            end
        end
    end
end

"""
    _forceclose_cleanup_shared!(server, file, apath)

Clean up sibling file entries and the shared worker entry after force-killing
a shared worker. Must be called under server.lock.
"""
function _forceclose_cleanup_shared!(server, file, apath)
    entry = get(server.shared_workers, file.worker_key, nothing)
    if entry !== nothing
        for sibling_path in entry.users
            sibling_path == apath && continue
            sibling = get(server.workers, sibling_path, nothing)
            if sibling !== nothing
                if sibling.timeout_timer !== nothing
                    close(sibling.timeout_timer)
                end
                delete!(server.workers, sibling_path)
                _gc_cache_files(joinpath(dirname(sibling_path), ".cache"))
            end
        end
        delete!(server.shared_workers, file.worker_key)
    end
end

# Close and forceclose.

function close!(server::Server)
    lock(server.lock) do
        for path in collect(keys(server.workers))
            close!(server, path)
        end
        # Stop any remaining shared workers (should already be empty if all
        # files were closed, but clean up defensively)
        for (key, entry) in server.shared_workers
            WorkerIPC.stop(entry.worker)
        end
        empty!(server.shared_workers)
    end
    rm(server.sandbox_base; force = true, recursive = true)
end

"""
    close!(server::Server, path::String)

Closes the `File` at `path`. Returns `true` if the
file was closed and `false` if it did not exist, which
can happen if it was closed by a timeout, for example.
"""
function close!(server::Server, path::String)
    try
        borrow_file!(server, path) do file
            transition!(file, FileState.Ready, FileState.Closing)
            if file.timeout_timer !== nothing
                close(file.timeout_timer)
            end
            if file.worker_key !== nothing
                try
                    WorkerIPC.call(
                        file.worker,
                        WorkerIPC.NotebookCloseRequest(file = file.path),
                    )
                catch err
                    @debug "NotebookCloseRequest failed for $(file.path)" exception = err
                end
            else
                WorkerIPC.stop(file.worker)
            end
            lock(server.lock) do
                _unregister_file!(server, file)
            end
            GC.gc()
        end
        return true
    catch err
        if err isa FileBusyError
            throw(
                UserError(
                    "Tried to close file \"$path\" but the corresponding worker is busy.",
                ),
            )
        elseif !(err isa NoFileEntryError)
            rethrow(err)
        else
            false
        end
    end
end

function forceclose!(server::Server, path::String)
    apath = abspath(path)
    file = lock(server.lock) do
        if haskey(server.workers, apath)
            return server.workers[apath]
        else
            throw(NoFileEntryError(apath))
        end
    end
    # If the worker is idle we can close normally.
    lock_attained = trylock(file.lock)
    try
        if lock_attained
            close!(server, path)
        else
            file.force_close_requested[] = true
            if file.worker_key !== nothing
                _forceclose_signal_siblings!(server, file, apath)
            end
            WorkerIPC.stop(file.worker)
            lock(server.lock) do
                if file.worker_key !== nothing
                    _forceclose_cleanup_shared!(server, file, apath)
                end
                delete!(server.workers, apath)
                on_change(server)
            end
        end
    finally
        lock_attained && unlock(file.lock)
    end
    return
end
