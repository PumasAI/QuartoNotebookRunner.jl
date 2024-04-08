include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/serialization.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 8

    cell = cells[8]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["data"]["text/plain"] == "2"
end
