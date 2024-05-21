using Test, QuartoNotebookWorker

@testset "QuartoNotebookWorker" begin
    # Just a dummy test for now. We can start adding real tests in follow-up PRs
    # that make changes to the worker code.
    @test QuartoNotebookWorker.Packages.is_precompiling() == false
end
