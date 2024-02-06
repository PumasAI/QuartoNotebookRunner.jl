include("../../utilities/prelude.jl")

@testset "error_configuration/01" begin
    server = Server()

    test_logger = Test.TestLogger()
    with_logger(test_logger) do
        qmd = joinpath(@__DIR__, "01.qmd")
        @test_throws ErrorException run!(server, qmd)
    end

    @test length(test_logger.logs) == 3

    log = test_logger.logs[1]
    @test log.level == Logging.Error
    @test log.message == "stopping notebook evaluation due to unexpected cell error."
    @test endswith(log.kwargs[:file], "01.qmd:9")
    @test occursin("no method matching", string(log.kwargs[:traceback]))

    log = test_logger.logs[2]
    @test log.level == Logging.Error
    @test log.message == "stopping notebook evaluation due to unexpected cell error."
    @test endswith(log.kwargs[:file], "01.qmd:13")
    @test occursin("integer division error", string(log.kwargs[:traceback]))

    log = test_logger.logs[3]
    @test log.level == Logging.Error
    @test log.message == "stopping notebook evaluation due to unexpected `show` error."
    @test endswith(log.kwargs[:file], "01.qmd:31")
    @test occursin("T failed to show.", string(log.kwargs[:traceback]))

    close!(server)
end
