include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/trailing_content.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 3

    cell = cells[1]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "A code block:"), cell["source"])

    cell = cells[2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    cell = cells[3]
    @test cell["cell_type"] == "markdown"
    @test any(line -> contains(line, "And some trailing content."), cell["source"])
end
