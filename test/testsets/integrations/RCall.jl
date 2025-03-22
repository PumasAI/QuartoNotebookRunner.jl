include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/RCall.qmd")) do json
    cells = json["cells"]
    cell = cells[4]
    output = cell["outputs"][1]

    @test !isempty(output["data"]["image/png"])

    @test cell["outputs"][1]["metadata"]["image/png"] ==
          Dict("width" => 600, "height" => 450)
end

# Don't run this on macOS CI, since that appears to be missing the required libs.
if !(get(ENV, "CI", "false") == "true" && Sys.isapple())
    test_example(joinpath(@__DIR__, "../../examples/integrations/RCallSVG.qmd")) do json
        cells = json["cells"]
        cell = cells[4]
        output = cell["outputs"][1]

        @test !isempty(output["data"]["image/svg+xml"])
        @test isempty(cell["outputs"][1]["metadata"])
    end
end
