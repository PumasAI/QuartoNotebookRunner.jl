baremodule NotebookInclude

import Base, Core
import ..QuartoNotebookWorker

# As defined by `MainInclude` to replicate the behaviour of the `Main` module in
# the REPL.
function include(fname::Base.AbstractString)
    isa(fname, Base.String) || (fname = Base.convert(Base.String, fname)::Base.String)
    ctx = QuartoNotebookWorker.NotebookState.current_context()
    ctx === Base.nothing && Base.error("No notebook context available")
    Base._include(Base.identity, ctx.mod, fname)
end

function eval(x)
    ctx = QuartoNotebookWorker.NotebookState.current_context()
    ctx === Base.nothing && Base.error("No notebook context available")
    Core.eval(ctx.mod, x)
end

end
