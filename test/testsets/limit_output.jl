include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/limit_output.qmd")) do json
    cells = json["cells"]
    text = cells[2]["outputs"][1]["data"]["text/plain"]
    @test contains(text, "…")
    @test contains(text, "⋮")
    @test contains(text, "⋱")
end
