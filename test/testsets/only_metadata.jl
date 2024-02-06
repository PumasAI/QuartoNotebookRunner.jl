include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/only_metadata.qmd")) do json
    @test length(json["cells"]) == 1
    @test json["cells"][1]["cell_type"] == "markdown"
    @test any(line -> contains(line, "Markdown content."), json["cells"][1]["source"])
end
