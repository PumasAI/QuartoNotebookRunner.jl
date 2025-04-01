module QuartoNotebookWorkerJSONExt

import QuartoNotebookWorker
import JSON: print

function QuartoNotebookWorker._ojs_define(::QuartoNotebookWorker.OJSDefine, kwargs)
    contents = QuartoNotebookWorker.ojs_convert(kwargs)
    return HTML() do io
        print(io, "<script type='ojs-define'>")
        JSON.print(io, Dict("contents" => contents))
        print(io, "</script>")
    end
end

end
