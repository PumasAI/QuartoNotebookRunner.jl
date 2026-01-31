@testitem "source_path" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "source_path.qmd"))
    RTS.validate_notebook(json)

    cell = json["cells"][2]
    data = cell["outputs"][1]["data"]
    @test contains(data["text/plain"], "source_path.qmd")

    QNR.close!(server)
end
