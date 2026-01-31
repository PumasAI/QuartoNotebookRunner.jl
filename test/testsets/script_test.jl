@testitem "script" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "script.jl"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test length(cells) == 3

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Markdown *content*."), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "Script files")

    cell = cells[3]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 0
    @test isempty(cell["outputs"])

    QNR.close!(server)
end
