@testitem "env_and_exeflags" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "env_and_exeflags.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test length(cells) == 5

    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "\"BAR\""

    cell = cells[4]
    @test cell["outputs"][1]["text"] == "\e[31mred\e[39m"

    QNR.close!(server)
end

@testitem "env_and_exeflags with env override" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    withenv("QUARTONOTEBOOKRUNNER_EXEFLAGS" => """["--color=no"]""") do
        json, server =
            RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "env_and_exeflags.qmd"))
        RTS.validate_notebook(json)

        cells = json["cells"]
        @test length(cells) == 5

        cell = cells[2]
        @test cell["outputs"][1]["data"]["text/plain"] == "\"BAR\""

        cell = cells[4]
        @test cell["outputs"][1]["text"] == "red"

        QNR.close!(server)
    end
end
