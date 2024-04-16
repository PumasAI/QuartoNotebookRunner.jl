include("../../utilities/prelude.jl")

test_example(
    joinpath(@__DIR__, "../../examples/integrations/R_code_blocks_with_RCall.qmd"),
) do json
    cells = json["cells"]

    @test occursin("RCall must be imported", cells[3]["outputs"][1]["traceback"][1])

    @test cells[8]["outputs"][1]["data"]["text/plain"] == "615.0"

    # plot
    @test !isempty(cells[11]["outputs"][1]["data"]["image/png"])

    # dataframe
    @test occursin("DataFrame", cells[14]["outputs"][1]["data"]["text/plain"])
    @test !isempty(cells[14]["outputs"][1]["data"]["text/html"])

    @test cells[17]["outputs"][1]["traceback"][1] ==
          "REvalError: Error: object 'x' not found"

    @test cells[19]["outputs"][1]["data"]["text/plain"] == "615.0"

    for (i, cell) in enumerate(cells)
        if endswith("code_prefix", cell["id"])
            @test cell["cell_type"] == "markdown"
            @test cell["source"][1] == "```r\n"
            @test cell["source"][end] == "```"
            following = cells[i+1]
            @test following["cell_type"] == "code"
            @test any(==("#| echo: false\n"), following["source"])

        end
    end

    @test contains(cells[20]["source"][end], "inline code: 124")
end
