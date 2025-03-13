include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/CairoMakie.qmd")) do json
    cells = json["cells"]
    cell = cells[6]

    px_per_inch = 96

    # the size metadata is just inches converted to CSS pixels, independent of pixel resolution
    @test cell["outputs"][1]["metadata"]["image/png"] ==
          Dict("width" => 4 * px_per_inch, "height" => 3 * px_per_inch)

    # the pixel resolution is controlled by px_per_unit and that reflects the dpi that is set
    px_per_unit_str = cells[end-1]["outputs"][1]["data"]["text/plain"]
    px_per_unit = parse(Float64, px_per_unit_str)
    @test px_per_unit == 150 / px_per_inch
end
