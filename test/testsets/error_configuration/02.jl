include("../../utilities/prelude.jl")

@testset "error_configuration/02" begin
    server = Server()

    qmd = joinpath(@__DIR__, "02.qmd")
    err = try
        run!(server, qmd)
    catch err
        err
    end
    @test err isa QuartoNotebookRunner.EvaluationError

    @test length(err.metadata) == 2

    meta = err.metadata[1]
    @test meta.kind == :cell
    @test endswith(meta.file, "02.qmd:9")
    @test occursin("no method matching", meta.traceback)

    meta = err.metadata[2]
    @test meta.kind == :cell
    @test endswith(meta.file, "02.qmd:14")
    @test occursin("integer division error", meta.traceback)

    close!(server)
end
