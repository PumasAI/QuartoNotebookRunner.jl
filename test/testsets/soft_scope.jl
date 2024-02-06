include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/soft_scope.qmd")) do json
    cells = json["cells"]
    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "55"
end
