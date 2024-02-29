include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/project.qmd")) do json
    cell = json["cells"][1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "Non-global project environment."), cell["source"])

    cell = json["cells"][2]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "false"

    cell = json["cells"][6]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test contains(cell["outputs"][1]["text"], "Activating")
    @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))

    cell = json["cells"][8]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

    cell = json["cells"][10]
    @test cell["cell_type"] == "code"
    @test isempty(cell["outputs"])

    cell = json["cells"][12]
    @test cell["cell_type"] == "code"
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "true"
end
