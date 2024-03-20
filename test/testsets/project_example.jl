include("../utilities/prelude.jl")

for file in (
    "project_env.qmd",
    "project_exeflags.qmd",
    "project/project_default.qmd",
    "project/dir/project_default.qmd",
)
    test_example(joinpath(@__DIR__, "../examples", file)) do json
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
    end
end
