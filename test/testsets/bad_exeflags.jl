include("../utilities/prelude.jl")

@testset "bad exeflags" begin
    s = QuartoNotebookRunner.Server()
    path = joinpath(@__DIR__, "../examples/bad_exeflags.qmd")
    if VERSION < v"1.8"
        @test_throws ErrorException QuartoNotebookRunner.run!(s, path)
    else
        @test_throws "--unknown-flag" QuartoNotebookRunner.run!(s, path)
    end
    path = joinpath(@__DIR__, "../examples/bad_juliaup_channel.qmd")
    if VERSION < v"1.8"
        @test_throws ErrorException QuartoNotebookRunner.run!(s, path)
    else
        @test_throws "Invalid Juliaup channel `unknown`" QuartoNotebookRunner.run!(s, path)
    end
end
