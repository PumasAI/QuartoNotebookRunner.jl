include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/text_plain_mimetypes.qmd")) do json
    @test length(json["cells"]) == 9

    cell = json["cells"][1]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][2]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["execution_count"] == 1
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = json["cells"][3]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][4]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["execution_count"] == 1
    @test cell["outputs"][1]["data"]["text/plain"] == "\"string\""

    cell = json["cells"][5]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][6]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["execution_count"] == 1
    @test contains(cell["outputs"][1]["data"]["text/plain"], "5-element Vector")

    cell = json["cells"][7]
    @test cell["cell_type"] == "markdown"

    cell = json["cells"][8]
    @test cell["cell_type"] == "code"
    @test cell["execution_count"] == 1
    @test cell["outputs"][1]["output_type"] == "execute_result"
    @test cell["outputs"][1]["execution_count"] == 1
    @test contains(cell["outputs"][1]["data"]["text/plain"], "Dict{Char")
end
