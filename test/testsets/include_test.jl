@testitem "include" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "include.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test length(cells) == 3

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test cell["outputs"][2]["output_type"] == "execute_result"
    @test contains(cell["outputs"][2]["data"]["text/plain"], "10×10")

    QNR.close!(server)
end
