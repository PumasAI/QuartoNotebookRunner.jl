@testitem "limit_output" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "limit_output.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    text = cells[2]["outputs"][1]["data"]["text/plain"]
    @test contains(text, "…")
    @test contains(text, "⋮")
    @test contains(text, "⋱")

    QNR.close!(server)
end
