@testitem "julia-1.9.4" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "julia-1.9.4.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test cells[end-1]["outputs"][1]["data"]["text/plain"] == repr(v"1.9.4")
    @test json["metadata"]["language_info"]["version"] == "1.9.4"

    QNR.close!(server)
end

@testitem "julia-1.10.7" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "julia-1.10.7.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test cells[end-1]["outputs"][1]["data"]["text/plain"] == repr(v"1.10.7")
    @test json["metadata"]["language_info"]["version"] == "1.10.7"

    QNR.close!(server)
end

@testitem "julia-1.11.2" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "julia-1.11.2.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    @test cells[end-1]["outputs"][1]["data"]["text/plain"] == repr(v"1.11.2")
    @test json["metadata"]["language_info"]["version"] == "1.11.2"

    QNR.close!(server)
end

@testitem "julia-1.11.2 with env override" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    withenv("QUARTONOTEBOOKRUNNER_EXEFLAGS" => "[\"+1.9.4\"]") do
        json, server =
            RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "julia-1.11.2.qmd"))
        RTS.validate_notebook(json)

        cells = json["cells"]
        @test cells[end-1]["outputs"][1]["data"]["text/plain"] == repr(v"1.11.2")
        @test json["metadata"]["language_info"]["version"] == "1.11.2"

        QNR.close!(server)
    end
end
