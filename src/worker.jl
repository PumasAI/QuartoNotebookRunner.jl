function worker_init(f::File, options::Dict)
    return quote
        let QNW = Main.QuartoNotebookWorker
            QNW.NotebookState.PROJECT[] = Base.active_project()
            QNW.NotebookState.OPTIONS[] = $(options)
            QNW.NotebookState.define_notebook_module!(Main)
            global refresh!(args...) = QNW.refresh!($(f.path), $(options), args...)
        end
        nothing
    end
end
