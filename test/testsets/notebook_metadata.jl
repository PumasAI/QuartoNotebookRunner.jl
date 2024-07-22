include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/notebook_metadata.qmd")) do json
    cells = json["cells"]

    cell = cells[4]
    @test cell["outputs"][1]["data"]["text/plain"] == "true"

    cell = cells[11]
    @test cell["outputs"][1]["data"]["text/plain"] == "true"
end
