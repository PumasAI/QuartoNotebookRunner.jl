using Logging, Test, QuartoNotebookRunner

@testset "error_configuration/02" begin
    server = Server()

    test_logger = Test.TestLogger()
    with_logger(test_logger) do
        qmd = joinpath(@__DIR__, "02.qmd")
        @test_throws ErrorException run!(server, qmd)
    end

    @test length(test_logger.logs) == 2

    log = test_logger.logs[1]
    @test log.level == Logging.Error
    @test log.message == "stopping notebook evaluation due to unexpected cell error."
    @test endswith(log.kwargs[:file], "02.qmd:9")
    @test occursin("no method matching", string(log.kwargs[:traceback]))

    log = test_logger.logs[2]
    @test log.level == Logging.Error
    @test log.message == "stopping notebook evaluation due to unexpected cell error."
    @test endswith(log.kwargs[:file], "02.qmd:14")
    @test occursin("integer division error", string(log.kwargs[:traceback]))

    close!(server)
end
