include("../../utilities/prelude.jl")

@testset "error_configuration/01" begin
    server = Server()

    qmd = joinpath(@__DIR__, "01.qmd")
    err = try
        run!(server, qmd)
    catch err
        err
    end
    @test err isa QuartoNotebookRunner.EvaluationError

    @test length(err.metadata) == 4

    meta = err.metadata[1]
    @test meta.kind == :inline
    @test meta.file == "inline: `{julia} div(1, 0)`"
    @test occursin("integer division error", meta.traceback)

    meta = err.metadata[2]
    @test meta.kind == :cell
    @test endswith(meta.file, "01.qmd:11")
    @test occursin("no method matching", meta.traceback)

    meta = err.metadata[3]
    @test meta.kind == :cell
    @test endswith(meta.file, "01.qmd:15")
    @test occursin("integer division error", meta.traceback)

    meta = err.metadata[4]
    @test meta.kind == :show
    @test endswith(meta.file, "01.qmd:33")
    @test occursin("T failed to show.", meta.traceback)

    close!(server)
end
