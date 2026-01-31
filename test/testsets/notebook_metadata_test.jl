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
