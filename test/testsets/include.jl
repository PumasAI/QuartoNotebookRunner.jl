include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/include.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 2

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test cell["outputs"][2]["output_type"] == "execute_result"
    @test contains(cell["outputs"][2]["data"]["text/plain"], "10×10")
end
