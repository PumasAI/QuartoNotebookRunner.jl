if VERSION >= v"1.10"
    include("../utilities/prelude.jl")

    test_example(joinpath(@__DIR__, "../examples/display.qmd")) do json
        cells = json["cells"]
        @test length(cells) == 5

        cell = cells[4]
        outputs = cell["outputs"]
        @test length(outputs) == 2

        @test outputs[1]["output_type"] == "display_data"
        @test haskey(outputs[1]["data"], "image/png")

        @test outputs[2]["output_type"] == "display_data"
        @test haskey(outputs[2]["data"], "image/png")
    end
end
