@testitem "a cell that leaves a process running still finishes" tags = [:notebook] setup =
    [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    path = joinpath(@__DIR__, "..", "examples", "lingering_process.qmd")
    json, server = RTS.run_notebook(path)

    cell = only(filter(cell -> cell["cell_type"] == "code", json["cells"]))
    @test contains(cell["outputs"][1]["text"], "before the process starts")
    @test contains(cell["outputs"][1]["text"], "after the process starts")

    # The first run pays for worker startup, so time a second one against the
    # warm worker. The process the first run started sleeps for 90 seconds, and
    # a capture that waits for its pipe to reach the end waits for that.
    buffer = IOBuffer()
    elapsed = @elapsed QNR.run!(server, path; output = buffer, showprogress = false)
    QNR.close!(server, path)

    @test elapsed < 60
end
