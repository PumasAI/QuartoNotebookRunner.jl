function worker_init(f::File, options::Dict)
    project = QuartoNotebookWorker.LOADER_ENV[]
    quote
        push!(LOAD_PATH, $(project))

        let QNW = Base.require(
                Base.PkgId(
                    Base.UUID("38328d9c-a911-4051-bc06-3f7f556ffeda"),
                    "QuartoNotebookWorker",
                ),
            )
            global refresh!(args...) = QNW.refresh!($(f.path), $(options), args...)
            global render(args...) = QNW.render(args...)
        end

        nothing
    end
end
