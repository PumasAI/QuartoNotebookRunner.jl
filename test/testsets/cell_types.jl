include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/cell_types.qmd")) do json
    @test length(json["cells"]) == 6

    cell = json["cells"][1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Values:"), cell["source"])
    @test contains(cell["source"][1], "\n")
    @test !contains(cell["source"][end], "\n")

    cell = json["cells"][2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["execution_count"] == 1
    @test cell["outputs"][1]["data"]["text/plain"] == "1"
    @test length(cell["outputs"][1]["data"]) == 1

    cell = json["cells"][3]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Output streams:"), cell["source"])

    cell = json["cells"][4]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "1")

    cell = json["cells"][5]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Errors:"), cell["source"])

    cell = json["cells"][6]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "error"
    @test cell["outputs"][1]["ename"] == "DivideError"
    @test cell["outputs"][1]["evalue"] == "DivideError()"
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "div")
    @test count("top-level scope", traceback) == 1
    @test count(r"cell_types\.(qmd|jl):", traceback) == 1
end
