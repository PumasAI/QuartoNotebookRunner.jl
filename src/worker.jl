function worker_init(f::File, options::Dict)
    return quote
        # Issue #192
        #
        # Malt itself uses a new task for each `remote_eval` and because of
        # this, random number streams are not consistent across runs even if
        # seeded, as each task introduces a new state for its task-local RNG.
        # As a workaround, we feed all `remote_eval` requests through these
        # channels, such that the task executing code is always the same.
        const stable_execution_task_channel_out = Channel()
        const stable_execution_task_channel_in = Channel() do chan
            for expr in chan
                result = Core.eval(Main, expr)
                put!(stable_execution_task_channel_out, result)
            end
        end

        let QNW = Main.QuartoNotebookWorker
            QNW.NotebookState.PROJECT[] = Base.active_project()
            QNW.NotebookState.OPTIONS[] = $(options)
            QNW.NotebookState.define_notebook_module!(Main)
            global refresh!(args...) = QNW.refresh!($(f.path), $(options), args...)
            global render(args...; kwargs...) = QNW.render(args...; kwargs...)
            global revise_hook() = QNW.revise_hook()
        end

        nothing
    end
end
