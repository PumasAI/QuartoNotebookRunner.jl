@testitem "a worker writing to stdout still exits promptly" tags = [:socket] setup =
    [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    # Nothing reads the worker's stdout after the startup handshake, so enough
    # output fills the pipe and the worker can no longer exit. `stop` then has
    # to wait out its timeout and kill the process.
    path = joinpath(@__DIR__, "..", "examples", "worker_stdout.qmd")
    _, server = RTS.run_notebook(path)

    sleep(3)
    elapsed = @elapsed QNR.close!(server, path)

    @test elapsed < 10
end
