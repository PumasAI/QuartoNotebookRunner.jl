function worker_init(f::File, options::Dict)
    project = WorkerSetup.LOADER_ENV[]
    return lock(WorkerSetup.WORKER_SETUP_LOCK) do
        return quote
            # issue #192
            # Malt itself uses a new task for each `remote_eval` and because of this, random number streams
            # are not consistent across runs even if seeded, as each task introduces a new state for its
            # task-local RNG. As a workaround, we feed all `remote_eval` requests through these channels, such
            # that the task executing code is always the same.
            const stable_execution_task_channel_out = Channel()
            const stable_execution_task_channel_in = Channel() do chan
                for expr in chan
                    result = Core.eval(Main, expr)
                    put!(stable_execution_task_channel_out, result)
                end
            end

            push!(LOAD_PATH, $(project))

            # When a manifest already exists ensure the environment is able to
            # be precompiled with the version of Julia that is using it. If we
            # just proceed to import `QuartoNotebookWorker` directly then these
            # potential errors are not passed back to the server process, thus
            # hiding the issues.
            let
                _isfile(::Any) = false
                _isfile(s::AbstractString) = Base.isfile(s)
                project = Base.active_project()
                if _isfile(project)
                    manifest = Base.project_file_manifest_path(project)
                    if _isfile(manifest)
                        pushfirst!(LOAD_PATH, "@stdlib")
                        import Pkg
                        popfirst!(LOAD_PATH)
                        Pkg.precompile(; strict = true) # Throws an error when it fails.
                    end
                end
            end

            let QNW = task_local_storage(:QUARTO_NOTEBOOK_WORKER_OPTIONS, $(options)) do
                    Base.require(
                        Base.PkgId(
                            Base.UUID("38328d9c-a911-4051-bc06-3f7f556ffeda"),
                            "QuartoNotebookWorker",
                        ),
                    )
                end
                QNW.NotebookState.define_notebook_module!(Main)
                global refresh!(args...) = QNW.refresh!($(f.path), $(options), args...)
                global render(args...; kwargs...) = QNW.render(args...; kwargs...)
            end

            nothing
        end
    end
end
