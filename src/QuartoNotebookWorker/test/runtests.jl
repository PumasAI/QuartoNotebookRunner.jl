using Test, QuartoNotebookWorker

@testset "QuartoNotebookWorker" begin
    @test QuartoNotebookWorker.Packages.is_precompiling() == false
end
