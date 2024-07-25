include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/warnings.qmd")) do json
    cells = json["cells"]

    cell = cells[2]
    @test isempty(cell["outputs"])

    for cell in (cells[4], cells[6])
        outputs = cell["outputs"]
        @test length(outputs) == 1
        @test outputs[1]["output_type"] == "stream"
        @test contains(outputs[1]["text"], "info")
        @test contains(outputs[1]["text"], "warn")
        @test contains(outputs[1]["text"], "error")
        @test contains(outputs[1]["text"], "warnings.qmd")
    end
end
