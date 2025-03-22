include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/io_context.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 3

    cell = cells[2]
    output = cell["outputs"][1]
    @test output["output_type"] == "stream"
    @test output["name"] == "stdout"
    @test output["text"] == "M(22)"
end
