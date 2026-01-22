if VERSION >= v"1.10"
    include("../../utilities/prelude.jl")

    test_example(joinpath(@__DIR__, "../../examples/integrations/Plots.qmd")) do json
        cells = json["cells"]
        cell = cells[6]
        output = cell["outputs"][1]

        @test !isempty(output["data"]["image/png"])
        @test !isempty(output["data"]["image/svg+xml"])
        @test !isempty(output["data"]["text/html"])

        metadata = cell["outputs"][1]["metadata"]["image/png"]
        # Plots does not seem to follow standard dpi rules so the values don't match Makie,
        # also at some point one of the pixel values shifted by 1 without an obvious reason,
        # so now we are a little lenient as we don't want to depend on Plots.jl's exact output.
        @test isapprox(metadata["width"], 575, atol=2)
        @test isapprox(metadata["height"], 432, atol=2)
    end

    test_example(joinpath(@__DIR__, "../../examples/integrations/PlotsPDF.qmd")) do json
        cells = json["cells"]

        cell = cells[4]
        output = cell["outputs"][1]

        @test !isempty(output["data"]["application/pdf"])
    end
end
