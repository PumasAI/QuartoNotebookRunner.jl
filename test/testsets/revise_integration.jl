include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/revise_integration.qmd")) do json
    cells = json["cells"]

    cell = cells[10]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = cells[14]
    @test cell["outputs"][1]["data"]["text/plain"] == "2"
end
