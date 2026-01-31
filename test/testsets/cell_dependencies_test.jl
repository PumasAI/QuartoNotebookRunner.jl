@testitem "cell_dependencies" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "cell_dependencies.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = cells[4]
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    cell = cells[6]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test count("not defined", traceback) == 1

    cell = cells[8]
    @test cell["outputs"][1]["data"]["text/plain"] == "Any[]"

    cell = cells[10]
    @test contains(cell["outputs"][1]["data"]["text/plain"], "Vector{Any}")
    @test contains(cell["outputs"][1]["data"]["text/plain"], ":item")

    cell = cells[12]
    @test cell["outputs"][1]["data"]["text/plain"] == "\"item\""

    QNR.close!(server)
end
