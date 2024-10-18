module QuartoNotebookWorkerJSONExt

import QuartoNotebookWorker
import ..JSON

function QuartoNotebookWorker._ojs_define(::QuartoNotebookWorker.OJSDefine, kwargs)
    contents = QuartoNotebookWorker.ojs_convert(kwargs)
    json = JSON.json(Dict("contents" => contents))
    return HTML("<script type='ojs-define'>$(json)</script>")
end

end
