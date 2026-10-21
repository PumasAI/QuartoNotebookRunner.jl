@testitem "notebook_metadata" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "notebook_metadata.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[4]
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    cell = cells[11]
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    QNR.close!(server)
end

@testitem "notebook_options metadata" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    D = Dict{String,Any}
    frontmatter = D("custom" => D("a" => 1), "params" => D("p" => 1))

    metadata = QNR._extract_relevant_options(frontmatter, D())["format"]["metadata"]
    @test metadata["custom"] == D("a" => 1)
    @test metadata["params"] == D("p" => 1)

    options = D(
        "format" => D(
            "metadata" => D(
                "custom" => D("a" => 1, "b" => 2),
                "params" => D("p" => 1, "q" => 2),
            ),
        ),
        "params" => D("q" => 3),
    )
    metadata = QNR._extract_relevant_options(frontmatter, options)["format"]["metadata"]
    @test metadata["custom"] == D("a" => 1, "b" => 2)
    @test metadata["params"] == D("p" => 1, "q" => 3)
end

@testitem "notebook_options metadata via quarto" tags = [:notebook] begin
    # quarto's server launcher calls `redirect_stdout(::Pipe)`, which Julia 1.6 lacks.
    if VERSION >= v"1.7"
        dir = joinpath(@__DIR__, "..", "examples", "quarto_integration", "metadata")
        cmd = addenv(
            `quarto render $(joinpath(dir, "metadata.qmd")) --to md`,
            "QUARTO_JULIA_PROJECT" => normpath(joinpath(@__DIR__, "..", "..")),
        )
        run(cmd)
        outputfile = joinpath(dir, "metadata.md")
        @test occursin(
            "from_document=document, from_project=project, shared=document",
            read(outputfile, String),
        )
        rm(outputfile)
    end
end
