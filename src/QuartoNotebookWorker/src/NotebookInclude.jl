baremodule NotebookInclude

import Base, Core
import ..QuartoNotebookWorker

# As defined by `MainInclude` to replicate the behaviour of the `Main` module in
# the REPL.
function include(fname::Base.AbstractString)
    isa(fname, Base.String) || (fname = Base.convert(Base.String, fname)::Base.String)
    Base._include(
        Base.identity,
        QuartoNotebookWorker.NotebookState.notebook_module(),
        fname,
    )
end
eval(x) = Core.eval(QuartoNotebookWorker.NotebookState.notebook_module(), x)

end
