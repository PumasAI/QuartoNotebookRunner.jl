using Test
import QuartoNotebookRunner

@testset "QuartoNotebookWorker" begin
    @test success(QuartoNotebookRunner.WorkerSetup.test())
end
