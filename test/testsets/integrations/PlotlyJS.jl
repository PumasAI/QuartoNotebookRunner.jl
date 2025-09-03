if VERSION >= v"1.10"
    include("../../utilities/prelude.jl")

    if Sys.iswindows()
        # There are issues with the Kaleido_jll v0.2 build on Windows, skip for now.
        @info "Skipping PlotlyJS.jl tests on Windows"
    else
        test_example(joinpath(@__DIR__, "../../examples/integrations/PlotlyJS.qmd")) do json
            cells = json["cells"]
            preamble_cell = cells[5]
            outputs = preamble_cell["outputs"]
            @test length(outputs) == 1
            data = outputs[1]["data"]
            @test keys(data) == Set(["text/html", "text/plain"])
            @test startswith(data["text/html"], "<script type=\"text/javascript\">")
            @test occursin("require.undef(\"plotly\")", data["text/html"])
            for nth in (6, 9)
                cell = cells[nth]
                outputs = cell["outputs"]
                @test length(outputs) == 1
                data = outputs[1]["data"]
                @test haskey(data, "image/png")
                @test haskey(data, "image/svg+xml")
                @test haskey(data, "text/html")
                @test startswith(data["text/html"], "<div>")
            end
        end
    end
end
