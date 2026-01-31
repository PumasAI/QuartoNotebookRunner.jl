@testitem "empty_notebook" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "empty_notebook.qmd"))
    RTS.validate_notebook(json)

    @test length(json["cells"]) == 1
    @test json["cells"][1]["cell_type"] == "markdown"
    @test json["cells"][1]["source"] == []

    QNR.close!(server)
end
