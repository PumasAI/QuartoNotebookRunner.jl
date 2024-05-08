module QuartoNotebookWorkerReviseExt

import Revise
import QuartoNotebookWorker

# TODO: this is just for debugging that extension loading works. Remove once
# real tests are written.
function __init__()
    @info "extension has been loaded" Revise QuartoNotebookWorker
end

end
