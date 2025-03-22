# Try load `Revise` first, since we want to be able to track changes in the
# worker package and it needs to be loaded prior to any packages to track.
try
    import Revise
catch error
    @info "Revise not available."
end

import Pkg
let qnw = ENV["QUARTONOTEBOOKWORKER_PACKAGE"]
    cd(qnw)
    Pkg.develop(; path = qnw)
    Pkg.precompile()
end

import QuartoNotebookWorker
QuartoNotebookWorker.NotebookState.define_notebook_module!()

# Attempt to import some other useful packages.
try
    import Debugger
catch error
    @info "Debugger not available."
end
try
    import TestEnv
catch error
    @info "TestEnv not available."
end
