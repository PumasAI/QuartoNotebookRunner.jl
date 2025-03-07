import Pkg
let qnw = ENV["QUARTONOTEBOOKWORKER_PACKAGE"]
    cd(qnw)
    Pkg.develop(; path = qnw)
    Pkg.precompile()
    Pkg.test("QuartoNotebookWorker")
end
