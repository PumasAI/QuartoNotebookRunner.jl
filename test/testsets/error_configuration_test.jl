@testitem "error_configuration/01" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    server = QNR.Server()

    qmd = joinpath(@__DIR__, "error_configuration", "01.qmd")
    err = try
        QNR.run!(server, qmd)
    catch e
        e
    end
    @test err isa QNR.EvaluationError

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

    QNR.close!(server)
end

@testitem "error_configuration/02" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    server = QNR.Server()

    qmd = joinpath(@__DIR__, "error_configuration", "02.qmd")
    err = try
        QNR.run!(server, qmd)
    catch e
        e
    end
    @test err isa QNR.EvaluationError

    @test length(err.metadata) == 2

    meta = err.metadata[1]
    @test meta.kind == :cell
    @test endswith(meta.file, "02.qmd:9")
    @test occursin("no method matching", meta.traceback)

    meta = err.metadata[2]
    @test meta.kind == :cell
    @test endswith(meta.file, "02.qmd:14")
    @test occursin("integer division error", meta.traceback)

    QNR.close!(server)
end
