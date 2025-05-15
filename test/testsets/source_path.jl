include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/source_path.qmd")) do json
    cell = json["cells"][2]
    data = cell["outputs"][1]["data"]
    @test contains(data["text/plain"], "source_path.qmd")
end
