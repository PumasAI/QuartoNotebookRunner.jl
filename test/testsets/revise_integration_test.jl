@testitem "revise_integration" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "revise_integration.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[10]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = cells[14]
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    QNR.close!(server)
end
