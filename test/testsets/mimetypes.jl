if VERSION >= v"1.10"
    include("../utilities/prelude.jl")

    test_example(joinpath(@__DIR__, "../examples/mimetypes.qmd")) do json
        cells = json["cells"]

        cell = cells[4]
        @test !isempty(cell["outputs"][1]["data"]["image/png"])
        @test !isempty(cell["outputs"][1]["data"]["text/html"])
        metadata = cell["outputs"][1]["metadata"]["image/png"]
        @test metadata["width"] > 0
        @test metadata["height"] > 0

        cell = cells[6]
        @test !isempty(cell["outputs"][1]["data"]["image/svg+xml"])
        @test !isempty(cell["outputs"][1]["data"]["image/png"])

        cell = cells[8]
        @test !isempty(cell["outputs"][1]["data"]["text/plain"])
        @test !isempty(cell["outputs"][1]["data"]["text/html"])

        cell = cells[10]
        @test cell["outputs"][1]["output_type"] == "stream"
        @test !isempty(cell["outputs"][1]["text"])

        cell = cells[12]
        @test !isempty(cell["outputs"][1]["data"]["text/plain"])
        @test !isempty(cell["outputs"][1]["data"]["text/html"])

        cell = cells[14]
        @test !isempty(cell["outputs"][1]["data"]["text/plain"])
        @test !isempty(cell["outputs"][1]["data"]["text/latex"])

        md = cell["outputs"][1]["data"]["text/markdown"]
        @test !isempty(md)
        @test !startswith(md, "\$\$")
        @test !endswith(md, "\$\$")
    end

    test_example(
        joinpath(@__DIR__, "../examples/mimetypes.qmd"),
        to_format("typst"),
    ) do json
        cells = json["cells"]

        cell = cells[14]
        @test !isempty(cell["outputs"][1]["data"]["text/plain"])
        @test !isempty(cell["outputs"][1]["data"]["text/latex"])
        md = cell["outputs"][1]["data"]["text/markdown"]
        @test startswith(md, "\$\$")
        @test endswith(md, "\$\$")
    end
end
