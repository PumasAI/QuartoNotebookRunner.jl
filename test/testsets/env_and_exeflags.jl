include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/env_and_exeflags.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 4

    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "\"BAR\""

    cell = cells[4]
    @test cell["outputs"][1]["text"] == "red"
end

withenv("QUARTONOTEBOOKRUNNER_EXEFLAGS" => """["--color=yes"]""") do
    test_example(joinpath(@__DIR__, "../examples/env_and_exeflags.qmd")) do json
        cells = json["cells"]
        @test length(cells) == 4

        cell = cells[2]
        @test cell["outputs"][1]["data"]["text/plain"] == "\"BAR\""

        cell = cells[4]
        @test cell["outputs"][1]["text"] == "\e[31mred\e[39m"
    end
end
