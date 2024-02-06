include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/empty_notebook.qmd")) do json
    @test length(json["cells"]) == 1
    @test json["cells"][1]["cell_type"] == "markdown"
    @test json["cells"][1]["source"] == []
end
