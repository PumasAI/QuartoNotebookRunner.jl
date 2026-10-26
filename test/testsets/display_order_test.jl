@testitem "display order" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "display_order.qmd"))
    RTS.validate_notebook(json)

    summary(output) =
        output["output_type"] == "stream" ? (output["name"], output["text"]) :
        output["output_type"] == "display_data" ?
        ("display", output["data"]["text/plain"]) :
        (output["output_type"], get(get(output, "data", Dict()), "text/plain", ""))

    cells = filter(cell -> cell["cell_type"] == "code", json["cells"])

    @test summary.(cells[1]["outputs"]) == [
        ("stdout", "before\n"),
        ("display", "\"first\""),
        ("stdout", "between\n"),
        ("display", "\"second\""),
        ("stdout", "after\n"),
    ]

    outputs = summary.(cells[2]["outputs"])
    @test outputs[1:2] == [("stdout", "computing\n"), ("display", "\"shown\"")]
    @test outputs[3][1] == "stderr"
    @test contains(outputs[3][2], "done")
    @test outputs[4] == ("execute_result", "2")

    @test summary.(cells[3]["outputs"]) ==
          [("stdout", "one\n"), ("display", "\"shown\""), ("stdout", "two\n")]

    QNR.close!(server)
end
