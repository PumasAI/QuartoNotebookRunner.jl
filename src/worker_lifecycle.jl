# Worker initialization, refresh, and file creation.

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

    if file.worker_key !== nothing
        # Shared worker: cannot restart — it's shared with other notebooks
        if worker_dead
            error("Shared worker process died unexpectedly")
        end
        if config_changed
            @warn "Worker config changed for shared notebook $(file.path); ignoring (shared worker cannot be restarted)"
        end
    elseif config_changed || worker_dead
        WorkerIPC.stop(file.worker)
        exe, _exeflags = _julia_exe(exeflags)
        file.worker = cd(
            () -> WorkerIPC.Worker(;
                exe,
                exeflags = _exeflags,
                env = vcat(env, quarto_env),
                strict_manifest_versions = julia_config.strict_manifest_versions,
                sandbox_base = file.sandbox_base,
            ),
            dirname(file.path),
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
    _create_file(server, path, options)

Create a File for `path`. If `share_worker_process` is enabled in frontmatter,
reuse or create a shared worker via `server.shared_workers`.
"""
function _create_file(server::Server, path::String, options)
    parsed = _parsed_options(options)
    _, _, file_frontmatter = raw_text_chunks(path)
    merged_options = _extract_relevant_options(file_frontmatter, parsed)
    julia_config = julia_worker_config(merged_options)

    if julia_config.share_worker_process
        exeflags, env, quarto_env = _exeflags_and_env(merged_options)
        exe, _exeflags = _julia_exe(exeflags)
        key = WorkerKey(exe, exeflags, env, julia_config.strict_manifest_versions)

        entry = get!(server.shared_workers, key) do
            w = cd(
                () -> WorkerIPC.Worker(;
                    exe,
                    exeflags = _exeflags,
                    env = vcat(env, quarto_env),
                    strict_manifest_versions = julia_config.strict_manifest_versions,
                    sandbox_base = server.sandbox_base,
                ),
                dirname(path),
            )
            SharedWorkerEntry(w, Set{String}())
        end
        if !WorkerIPC.isrunning(entry.worker)
            entry.worker = cd(
                () -> WorkerIPC.Worker(;
                    exe,
                    exeflags = _exeflags,
                    env = vcat(env, quarto_env),
                    strict_manifest_versions = julia_config.strict_manifest_versions,
                    sandbox_base = server.sandbox_base,
                ),
                dirname(path),
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
        return File(path, options; sandbox_base = server.sandbox_base)
    end
end
