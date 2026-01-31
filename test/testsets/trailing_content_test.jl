@testitem "trailing_content" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "trailing_content.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test length(cells) == 3

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "A code block:"), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    cell = cells[3]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "And some trailing content."), cell["source"])

    QNR.close!(server)
end
