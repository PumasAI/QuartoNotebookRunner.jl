module QuartoNotebookWorkerPythonCallExt

import QuartoNotebookWorker
import PythonCall

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        #RCall_temp_files_ref[] = mktempdir()
        #configure()
        #QuartoNotebookWorker.add_package_loading_hook!(configure)
        #QuartoNotebookWorker.add_package_refresh_hook!(refresh)
        #QuartoNotebookWorker.add_post_eval_hook!(display_plots)
        #QuartoNotebookWorker.add_post_error_hook!(cleanup_temp_files)
    end
end

end
