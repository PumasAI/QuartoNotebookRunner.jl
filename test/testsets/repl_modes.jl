include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/repl_modes.qmd")) do json

    cells = json["cells"]
    @test length(cells) == 8

    if !Sys.iswindows()
        cell = cells[2]
        @test cell["outputs"][1]["text"] == "OK\n"
        @test cell["outputs"][1]["output_type"] == "stream"
        @test cell["outputs"][1]["name"] == "stdout"
    else
        # https://github.com/JuliaLang/julia/issues/23597
        cell = cells[4]
        @test contains(cell["outputs"][1]["text"], "OK")
    end

    cell = cells[6]
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "Status")
    @test contains(cell["outputs"][1]["text"], "Project.toml")

    cell = cells[8]
    @test cell["outputs"][1]["output_type"] == "stream"
    @test cell["outputs"][1]["name"] == "stdout"
    @test contains(cell["outputs"][1]["text"], "search")

    @test cell["outputs"][2]["output_type"] == "execute_result"
    @test contains(cell["outputs"][2]["data"]["text/plain"], "64-bit signed integer type")
    @test contains(
        cell["outputs"][2]["data"]["text/markdown"],
        "64-bit signed integer type",
    )
    @test contains(cell["outputs"][2]["data"]["text/html"], "64-bit signed integer type")
    @test contains(cell["outputs"][2]["data"]["text/latex"], "64-bit signed integer type")

end
