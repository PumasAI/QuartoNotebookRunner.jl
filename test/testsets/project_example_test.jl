@testitem "project_env" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "project_env.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Non-global project environment."), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "false"

    cell = cells[6]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))
    @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test isempty(cell["outputs"])

    cell = cells[10]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    QNR.close!(server)
end

@testitem "project_exeflags" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "project_exeflags.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Non-global project environment."), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "false"

    cell = cells[6]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))
    @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test isempty(cell["outputs"])

    cell = cells[10]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    QNR.close!(server)
end

@testitem "project/project_default" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(
        joinpath(@__DIR__, "..", "examples", "project", "project_default.qmd"),
    )
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Non-global project environment."), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "false"

    cell = cells[6]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))
    @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test isempty(cell["outputs"])

    cell = cells[10]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    QNR.close!(server)
end

@testitem "project/dir/project_default" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(
        joinpath(@__DIR__, "..", "examples", "project", "dir", "project_default.qmd"),
    )
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Non-global project environment."), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "false"

    cell = cells[6]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))
    @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test isempty(cell["outputs"])

    cell = cells[10]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    QNR.close!(server)
end
