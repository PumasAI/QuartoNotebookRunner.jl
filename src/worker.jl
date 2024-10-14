function worker_init(f::File, options::Dict)
    project = WorkerSetup.LOADER_ENV[]
    return lock(WorkerSetup.WORKER_SETUP_LOCK) do
        return quote
            # issue #192
            # Malt itself uses a new task for each `remote_eval` and because of this, random number streams
            # are not consistens across runs even if seeded, as each task introduces a new state for its
            # task-local RNG. As a workaround, we use feed all `remote_eval` requests through these channels, such
            # that the task executing code is always the same.
            var"__stable_execution_task_channel_out" = Channel()
            var"__stable_execution_task_channel_in" = Channel() do chan
                for expr in chan
                    result = Core.eval(Main, expr)
                    put!(var"__stable_execution_task_channel_out", result)
                end
            end

            push!(LOAD_PATH, $(project))

            let QNW = task_local_storage(:QUARTO_NOTEBOOK_WORKER_OPTIONS, $(options)) do
                    Base.require(
                        Base.PkgId(
                            Base.UUID("38328d9c-a911-4051-bc06-3f7f556ffeda"),
                            "QuartoNotebookWorker",
                        ),
                    )
                end
                global refresh!(args...) = QNW.refresh!($(f.path), $(options), args...)
                global render(args...; kwargs...) = QNW.render(args...; kwargs...)
            end

            nothing
        end
    end
end
