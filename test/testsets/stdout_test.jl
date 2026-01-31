@testitem "stdout" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "stdout.qmd"))
    RTS.validate_notebook(json)

    @test length(json["cells"]) == 21

    cell = json["cells"][1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Printing:"), cell["source"])

    cell = json["cells"][2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test length(cell["outputs"]) == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "1")

    cell = json["cells"][3]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][4]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "string")

    cell = json["cells"][5]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][6]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "1")
    @test contains(cell["outputs"][1]["text"], "string")

    cell = json["cells"][7]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][8]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "Info:")
    @test contains(cell["outputs"][1]["text"], "info text")
    @test contains(cell["outputs"][1]["text"], "value = 1")

    cell = json["cells"][9]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][10]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "Warning:")
    @test contains(cell["outputs"][1]["text"], "warn text")
    @test contains(cell["outputs"][1]["text"], "value = 2")

    cell = json["cells"][11]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][12]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "Error:")
    @test contains(cell["outputs"][1]["text"], "error text")
    @test contains(cell["outputs"][1]["text"], "value = 3")

    cell = json["cells"][14]
    @test cell["outputs"][1]["data"]["text/plain"] == "\e[31mred\e[39m"

    # Warning suppression tests
    cell = json["cells"][16]
    @test isempty(cell["outputs"])

    for cell in (json["cells"][18], json["cells"][20])
        outputs = cell["outputs"]
        @test length(outputs) == 1
        @test outputs[1]["output_type"] == "stream"
        @test contains(outputs[1]["text"], "info")
        @test contains(outputs[1]["text"], "warn")
        @test contains(outputs[1]["text"], "error")
        @test contains(outputs[1]["text"], "stdout.qmd")
    end

    QNR.close!(server)
end
