# Worker initialization, refresh, and file creation.

function _start_worker(;
    exe,
    exeflags,
    env,
    strict_manifest_versions,
    sandbox_base,
    notebook_dir,
)
    cd(
        () ->
            WorkerIPC.Worker(; exe, exeflags, env, strict_manifest_versions, sandbox_base),
        notebook_dir,
    )
end

function init!(file::File, options::Dict)
    worker = file.worker
    exeflags, env, quarto_env = _exeflags_and_env(options)
    cwd = something(get(options, "cwd", nothing), dirname(file.path))
    project = _resolve_worker_project(exeflags, env, dirname(file.path))
    WorkerIPC.call(
        worker,
        WorkerIPC.NotebookInitRequest(;
            file = file.path,
            project,
            options,
            cwd,
            env_vars = quarto_env,
        ),
    )
end

"""
    _resolve_worker_project(exeflags, env, notebook_dir)

Determine the project the worker should activate based on its exeflags and env.
Checks `--project` in exeflags first, then `JULIA_PROJECT` in env.
Resolves `@.` by searching up from `notebook_dir`.
"""
function _resolve_worker_project(exeflags, env, notebook_dir)
    # Use the last --project flag since Julia ignores earlier duplicates.
    project = nothing
    for flag in exeflags
        if flag == "--project"
            project = "@."
        elseif startswith(flag, "--project=")
            project = flag[length("--project=")+1:end]
        end
    end
    if project !== nothing
        return project == "@." ? _resolve_at_dot(notebook_dir) : project
    end
    for entry in env
        if startswith(entry, "JULIA_PROJECT=")
            val = entry[length("JULIA_PROJECT=")+1:end]
            return val == "@." ? _resolve_at_dot(notebook_dir) : val
        end
    end
    return _resolve_at_dot(notebook_dir)
end

_resolve_at_dot(dir) = something(Base.current_project(dir), dir)

function refresh!(file::File, options::Dict)
    exeflags, env, quarto_env = _exeflags_and_env(options)
    julia_config = julia_worker_config(options)
    config_changed =
        exeflags != file.exeflags ||
        env != file.env ||
        julia_config.strict_manifest_versions != file.strict_manifest_versions
    worker_dead = !WorkerIPC.isrunning(file.worker)

    if file.attached
        # Attached session: owned by the user, never restarted. A dead
        # connection re-attaches; if the session is gone, degrade to a spawned
        # worker so rendering continues.
        if worker_dead
            worker = _try_attach(file.path)
            if worker !== nothing
                file.worker = worker
                file.source_code_hash = hash(VERSION)
                file.output_chunks = []
            else
                exe, _exeflags = _julia_exe(exeflags)
                file.worker = _start_worker(;
                    exe,
                    exeflags = _exeflags,
                    env = vcat(env, quarto_env),
                    strict_manifest_versions = julia_config.strict_manifest_versions,
                    sandbox_base = file.sandbox_base,
                    notebook_dir = dirname(file.path),
                )
                file.attached = false
                file.exe = exe
                file.exeflags = exeflags
                file.env = env
                file.strict_manifest_versions = julia_config.strict_manifest_versions
                file.source_code_hash = hash(VERSION)
                file.output_chunks = []
            end
        end
        if file.attached && config_changed
            @warn "Worker config changed for attached notebook $(file.path); ignoring (attached session is not restarted)"
        end
    elseif file.worker_key !== nothing
        # Shared worker: cannot restart — it's shared with other notebooks
        if worker_dead
            error("Shared worker process died unexpectedly")
        end
        if config_changed
            @warn "Worker config changed for shared notebook $(file.path); ignoring (shared worker cannot be restarted)"
        end
    elseif config_changed || worker_dead
        Logging.@debug "Restarting worker" path = file.path config_changed worker_dead
        WorkerIPC.stop(file.worker)
        exe, _exeflags = _julia_exe(exeflags)
        # If _start_worker throws, file.worker retains the stopped worker.
        # Next refresh! detects worker_dead and retries.
        file.worker = _start_worker(;
            exe,
            exeflags = _exeflags,
            env = vcat(env, quarto_env),
            strict_manifest_versions = julia_config.strict_manifest_versions,
            sandbox_base = file.sandbox_base,
            notebook_dir = dirname(file.path),
        )
        file.exe = exe
        file.exeflags = exeflags
        file.env = env
        file.strict_manifest_versions = julia_config.strict_manifest_versions
        file.source_code_hash = hash(VERSION)
        file.output_chunks = []
    end
    # Always send NotebookInitRequest to (re)initialize notebook context
    init!(file, options)
end

"""
    _attach_candidates(path)

Registry entries for sessions whose root contains the notebook at `path`,
deepest root first so a session rooted at a subproject shadows one rooted at the
repository. Empty when no session is registered.
"""
function _attach_candidates(path::String)
    notebook_dir = dirname(abspath(path))
    # Normalize through symlinks (e.g. macOS /tmp) so ancestor tests compare
    # real paths on both sides.
    notebook_real = isdir(notebook_dir) ? realpath(notebook_dir) : notebook_dir

    candidates = filter(WorkerIPC._read_attach_entries()) do fields
        root = get(fields, "root", "")
        isempty(root) && return false
        if get(fields, "protocol", "") != string(Int(WorkerIPC.PROTOCOL_VERSION))
            Logging.@debug "Skipping attach entry with mismatched protocol" fields
            return false
        end
        root_real = isdir(root) ? realpath(root) : return false
        rel = relpath(notebook_real, root_real)
        rel == "." || !startswith(rel, "..")
    end

    sort!(candidates; by = fields -> length(fields["root"]), rev = true)
    return candidates
end

"""
    _try_attach(path) -> Union{WorkerIPC.Worker,Nothing}

Connect to a live session serving the worker protocol for the notebook at
`path`, or `nothing` when none is reachable. Liveness is established by
connecting, so a stale registry entry is skipped after a failed connection.
"""
function _try_attach(path::String)
    for fields in _attach_candidates(path)
        port = parse(Int, fields["port"])
        pid = parse(Int, get(fields, "pid", "0"))
        try
            return WorkerIPC.Worker(port; pid)
        catch err
            Logging.@debug "Skipping unreachable attach session" port pid exception = err
        end
    end
    return nothing
end

"""
    _create_file(server, path, options)

Create a File for `path`. When a live user session serves the notebook's root
(and `QUARTONOTEBOOKRUNNER_NO_ATTACH` is unset), attach to it. Otherwise, if
`share_worker_process` is enabled, reuse or create a shared worker via
`server.shared_workers`; failing that, spawn a dedicated worker.
"""
function _create_file(server::Server, path::String, options)
    parsed = _parsed_options(options)
    _, _, file_frontmatter = raw_text_chunks(path)
    merged_options = _extract_relevant_options(file_frontmatter, parsed)
    julia_config = julia_worker_config(merged_options)

    if get(ENV, "QUARTONOTEBOOKRUNNER_NO_ATTACH", "false") != "true"
        worker = _try_attach(path)
        if worker !== nothing
            Logging.@debug "Creating attached worker file" path
            return File(
                path,
                options;
                sandbox_base = server.sandbox_base,
                worker,
                attached = true,
            )
        end
    end

    if julia_config.share_worker_process
        Logging.@debug "Creating shared worker file" path
        exeflags, env, quarto_env = _exeflags_and_env(merged_options)
        exe, _exeflags = _julia_exe(exeflags)
        key = WorkerKey(exe, exeflags, env, julia_config.strict_manifest_versions)

        entry = get!(server.shared_workers, key) do
            w = _start_worker(;
                exe,
                exeflags = _exeflags,
                env = vcat(env, quarto_env),
                strict_manifest_versions = julia_config.strict_manifest_versions,
                sandbox_base = server.sandbox_base,
                notebook_dir = dirname(path),
            )
            SharedWorkerEntry(w, Set{String}())
        end
        if !WorkerIPC.isrunning(entry.worker)
            entry.worker = _start_worker(;
                exe,
                exeflags = _exeflags,
                env = vcat(env, quarto_env),
                strict_manifest_versions = julia_config.strict_manifest_versions,
                sandbox_base = server.sandbox_base,
                notebook_dir = dirname(path),
            )
            empty!(entry.users)
        end
        push!(entry.users, path)
        return File(
            path,
            options;
            sandbox_base = server.sandbox_base,
            worker = entry.worker,
            worker_key = key,
        )
    else
        Logging.@debug "Creating dedicated worker file" path
        return File(path, options; sandbox_base = server.sandbox_base)
    end
end
