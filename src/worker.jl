function worker_init(f::File, options::Dict)
    project = WorkerSetup.LOADER_ENV[]
    return lock(WorkerSetup.WORKER_SETUP_LOCK) do
        return quote
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
