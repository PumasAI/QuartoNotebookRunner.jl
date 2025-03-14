include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/CairoMakie.qmd")) do json
    cells = json["cells"]
    cell = cells[6]

    px_per_inch = 96

    # the size metadata is just inches converted to CSS pixels, independent of pixel resolution
    @test cell["outputs"][1]["metadata"]["image/png"] ==
          Dict("width" => 4 * px_per_inch, "height" => 3 * px_per_inch)

    pngbytes = Base64.base64decode(cell["outputs"][1]["data"]["image/png"])
    @test QuartoNotebookRunner.png_image_metadata(pngbytes; phys_correction = false) ==
          (; width = 4 * 150, height = 3 * 150)
end
