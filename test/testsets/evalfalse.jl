include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/evalfalse.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 7
    @test isempty(cells[2]["outputs"])
    @test isempty(cells[4]["outputs"])
    @test !isempty(cells[6]["outputs"])
    @test occursin("should run", cells[6]["outputs"][1]["text"])
end
