@testitem "serialization" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "serialization.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test length(cells) == 9

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    QNR.close!(server)
end
