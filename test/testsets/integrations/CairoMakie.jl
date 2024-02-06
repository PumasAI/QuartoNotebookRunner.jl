include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/CairoMakie.qmd")) do json
    cells = json["cells"]
    cell = cells[6]
    @test cell["outputs"][1]["metadata"]["image/png"] ==
          Dict("width" => 4 * 150, "height" => 3 * 150)
end
