baremodule NotebookInclude

import Base, Core
import ..QuartoNotebookWorker

# As defined by `MainInclude` to replicate the behaviour of the `Main` module in
# the REPL.
function include(fname::Base.AbstractString)
    isa(fname, Base.String) || (fname = Base.convert(Base.String, fname)::Base.String)
    mod = QuartoNotebookWorker.NotebookState.current_notebook_module()
    mod === Base.nothing && Base.error("No notebook module in current context")
    Base._include(Base.identity, mod, fname)
end

function eval(x)
    mod = QuartoNotebookWorker.NotebookState.current_notebook_module()
    mod === Base.nothing && Base.error("No notebook module in current context")
    Core.eval(mod, x)
end

end
