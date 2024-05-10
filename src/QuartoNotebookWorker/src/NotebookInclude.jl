baremodule NotebookInclude

import Base, Core

# As defined by `MainInclude` to replicate the behaviour of the `Main` module in
# the REPL.
function include(fname::Base.AbstractString)
    isa(fname, Base.String) || (fname = Base.convert(Base.String, fname)::Base.String)
    Base._include(Base.identity, getfield(Main, :Notebook), fname)
end
eval(x) = Core.eval(getfield(Main, :Notebook), x)

end
