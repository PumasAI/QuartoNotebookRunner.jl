include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/cell_expansion.qmd")) do json
    @test length(json["cells"]) == 13

    cell = json["cells"][1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Cell Expansion"), cell["source"])
    @test contains(cell["source"][1], "\n")
    @test !contains(cell["source"][end], "\n")

    cell = json["cells"][2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test isempty(cell["outputs"])

    cell = json["cells"][3]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    output = cell["outputs"][1]
    @test output["output_type"] == "stream"
    @test output["name"] == "stdout"
    @test contains(output["text"], "print call")

    output = cell["outputs"][2]
    @test output["output_type"] == "display_data"
    @test output["data"]["text/plain"] == "\"display call\""

    output = cell["outputs"][3]
    @test output["output_type"] == "execute_result"
    @test output["data"]["text/plain"] == "\"return value\""

    source = cell["source"]
    @test source[1] == "#| layout-ncol: 2\n"
    @test source[2] == "# Fake code goes here."

    cell = json["cells"][5]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test isempty(cell["outputs"])

    cell = json["cells"][6]
    @test cell["id"] == "4_1"
    source = cell["source"]
    @test any(line -> contains(line, "#| layout-ncol: 1"), source)
    @test length(cell["outputs"]) == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = json["cells"][7]
    @test cell["id"] == "4_2"
    @test length(cell["outputs"]) == 2
    @test cell["outputs"][1]["output_type"] == "display_data"
    @test cell["outputs"][1]["data"]["text/plain"] == "2"
    @test cell["outputs"][2]["output_type"] == "execute_result"
    @test cell["outputs"][2]["data"]["text/plain"] == "2"

    cell = json["cells"][8]
    @test cell["id"] == "4_3"
    @test length(cell["outputs"]) == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "3"

    cell = json["cells"][9]
    @test cell["id"] == "4_4"
    @test length(cell["outputs"]) == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "4"

    cell = json["cells"][10]
    @test cell["id"] == "4_5"
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "## Header")
    source = cell["source"]
    @test any(line -> contains(line, "#| output: \"asis\""), source)
    @test any(line -> contains(line, "#| echo: false"), source)

    cell = json["cells"][13]
    @test cell["outputs"][1]["data"]["text/plain"] == "123"
end

test_example(joinpath(@__DIR__, "../examples/cell_expansion_errors.qmd")) do json
    cells = json["cells"]

    @test any(x -> occursin("MethodError", x), cells[3]["outputs"][]["traceback"])

    @test cells[6]["outputs"][]["data"]["text/plain"] == "\"no problem here\""

    @test any(x -> occursin("a nested thunk error", x), cells[7]["outputs"][]["traceback"])

    cell = cells[10]
    @test cell["outputs"][]["ename"] == "Invalid return value for expanded cell"
    @test any(
        x -> occursin("not a function of type `Base.Callable`", x),
        cell["outputs"][]["traceback"],
    )

    cell = cells[13]
    @test cell["outputs"][]["ename"] == "Invalid return value for expanded cell"
    @test any(x -> occursin("is not iterable", x), cell["outputs"][]["traceback"])

    cell = cells[16]
    @test cell["outputs"][]["ename"] == "Invalid return value for expanded cell"
    @test any(
        x -> occursin("must have a property `thunk`", x),
        cell["outputs"][]["traceback"],
    )

    cell = cells[19]
    @test cell["outputs"][]["ename"] == "Invalid return value for expanded cell"
    @test any(x -> occursin("`code` property", x), cell["outputs"][]["traceback"])

    cell = cells[22]
    @test cell["outputs"][]["ename"] == "Invalid return value for expanded cell"
    @test any(x -> occursin("`options` property", x), cell["outputs"][]["traceback"])
end
