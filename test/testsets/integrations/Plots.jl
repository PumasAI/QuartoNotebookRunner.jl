if VERSION >= v"1.10"
    include("../../utilities/prelude.jl")

    test_example(joinpath(@__DIR__, "../../examples/integrations/Plots.qmd")) do json
        cells = json["cells"]
        cell = cells[6]
        output = cell["outputs"][1]

        @test !isempty(output["data"]["image/png"])
        @test !isempty(output["data"]["image/svg+xml"])
        @test !isempty(output["data"]["text/html"])

        @test cell["outputs"][1]["metadata"]["image/png"] ==
              Dict("width" => 575, "height" => 432) # Plots does not seem to follow standard dpi rules so the values don't match Makie
    end

    test_example(joinpath(@__DIR__, "../../examples/integrations/PlotsPDF.qmd")) do json
        cells = json["cells"]

        cell = cells[4]
        output = cell["outputs"][1]

        @test !isempty(output["data"]["application/pdf"])
    end
end
