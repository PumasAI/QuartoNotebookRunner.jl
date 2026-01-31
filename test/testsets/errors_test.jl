@testitem "errors" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "errors.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    cell = cells[2]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "no method matching +")
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:6", traceback) == 1

    cell = cells[4]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "an error")
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:10", traceback) == 1

    cell = cells[6]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "an argument error")
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:14", traceback) == 1

    cell = cells[8]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "character literal contains multiple characters")
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:18", traceback) == (VERSION >= v"1.10" ? 2 : 1)

    cell = cells[10]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "unexpected")
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:22", traceback) == (VERSION >= v"1.10" ? 2 : 1)

    cell = cells[12]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test count("integer division error", traceback) == 1
    @test count("top-level scope", traceback) == 1
    @test count("errors.qmd:26", traceback) == 1
    @test count("(repeats 4 times)", traceback) == 1
    @test count("errors.qmd:27", traceback) == 1

    cell = cells[14]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test contains(traceback, "no method matching +(::SomeType, ::Int64)")

    cell = cells[18]

    outputs = cell["outputs"]
    @test length(outputs) == 4

    output = outputs[1]
    @test output["output_type"] == "error"
    @test output["ename"] == "text/plain showerror"
    @test length(output["traceback"]) == 11
    @test contains(output["traceback"][end], "multimedia.jl")

    output = outputs[2]
    @test output["output_type"] == "error"
    @test output["ename"] == "text/html showerror"
    @test length(output["traceback"]) == 9
    @test contains(output["traceback"][end], "multimedia.jl")

    output = outputs[3]
    @test output["output_type"] == "error"
    @test output["ename"] == "text/latex showerror"
    @test length(output["traceback"]) == 9
    @test contains(output["traceback"][end], "multimedia.jl")

    output = outputs[4]
    @test output["output_type"] == "error"
    @test output["ename"] == "image/svg+xml showerror"
    @test length(output["traceback"]) == 9
    @test contains(output["traceback"][end], "multimedia.jl")

    QNR.close!(server)
end
