@testitem "worker environments are keyed on the package path" tags = [:socket] begin
    import QuartoNotebookRunner as QNR

    IPC = QNR.WorkerIPC
    package = String(IPC.worker_package)

    # A second checkout of one version has the same `Project.toml` content at a
    # different path. Keying on the content alone hands both of them the same
    # environment, and that environment develops whichever path created it, so
    # one checkout ends up running the other's worker.
    other = mktempdir()
    cp(joinpath(package, "Project.toml"), joinpath(other, "Project.toml"))

    @test IPC._scratchspace_key(package) == IPC._scratchspace_key(package)
    @test IPC._scratchspace_key(package) != IPC._scratchspace_key(other)
end

@testitem "a worker that never reports a port ends with an error" tags = [:socket] setup =
    [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    # `-e` takes the place of the startup file, so this worker starts, never
    # listens, and never writes a port file. The server polls for that file, and
    # without a deadline it polls for as long as the worker lives.
    path = joinpath(@__DIR__, "..", "examples", "cell_types.qmd")
    withenv(
        "QUARTONOTEBOOKRUNNER_EXEFLAGS" => "[\"-e\", \"sleep(600)\"]",
        "QUARTONOTEBOOKRUNNER_WORKER_STARTUP_TIMEOUT" => "5",
    ) do
        server = QNR.Server()
        start = time()
        thrown = try
            QNR.run!(server, path; output = IOBuffer(), showprogress = false)
            nothing
        catch error
            error
        end
        elapsed = time() - start
        QNR.close!(server)

        @test thrown !== nothing
        @test contains(sprint(showerror, thrown), "Timed out after")
        @test elapsed < 120
    end
end

@testitem "the startup deadline rejects values that are not a wait" tags = [:socket] begin
    import QuartoNotebookRunner as QNR

    IPC = QNR.WorkerIPC

    @test IPC._worker_startup_timeout() == 600
    withenv("QUARTONOTEBOOKRUNNER_WORKER_STARTUP_TIMEOUT" => "30") do
        @test IPC._worker_startup_timeout() == 30
    end
    # Falling back to the default here would start every worker on a deadline
    # nobody asked for, and zero would fail every start before it began.
    for value in ("30s", "abc", "0", "-1")
        withenv("QUARTONOTEBOOKRUNNER_WORKER_STARTUP_TIMEOUT" => value) do
            @test_throws QNR.UserError IPC._worker_startup_timeout()
        end
    end
end
