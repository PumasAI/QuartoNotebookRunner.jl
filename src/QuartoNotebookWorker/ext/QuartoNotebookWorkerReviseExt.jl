module QuartoNotebookWorkerReviseExt

import Revise
import QuartoNotebookWorker as QNW

function __init__()
    @debug "extension has been loaded" Revise QuartoNotebookWorker
end

function QNW._revise_hook(::Nothing)
    isempty(Revise.revision_queue) || Base.invokelatest(Revise.revise; throw = true)
    return nothing
end

end
