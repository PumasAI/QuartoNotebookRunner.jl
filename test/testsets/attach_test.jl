@testitem "attach_to_live_session" tags = [:attach] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    # A live session serving the worker protocol, in a separate process like a
    # user's REPL. QuartoNotebookWorker resolves from its package directory on
    # the LOAD_PATH; its dependencies are stdlibs.
    worker_pkg = joinpath(dirname(@__DIR__), "..", "src", "QuartoNotebookWorker")
    worker_pkg = normpath(worker_pkg)

    registry = mktempdir()
    dir = mktempdir()
    qmd = joinpath(dir, "attach.qmd")
    write(
        qmd,
        """
        ---
        julia:
          attach: true
        ---

        ```{julia}
        Main.ATTACH_MARKER
        ```

        ```{julia}
        Main.ATTACH_COUNTER[] += 1
        ```
        """,
    )

    session_code = """
    push!(LOAD_PATH, $(repr(worker_pkg)))
    import QuartoNotebookWorker
    server = QuartoNotebookWorker.serve!(root = $(repr(dir)))
    ATTACH_MARKER = 42
    ATTACH_COUNTER = Ref(0)
    println("ATTACH_PORT=", server.port)
    flush(stdout)
    wait(server.task)
    """
    cmd = addenv(
        `$(Base.julia_cmd()) --startup-file=no -e $session_code`,
        "QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry,
    )
    proc = open(cmd, "r")

    try
        # Wait for the session to register.
        port_line = readline(proc)
        @test startswith(port_line, "ATTACH_PORT=")

        withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry) do
            first_output(json, nth) =
                join(json["cells"][nth]["outputs"][1]["data"]["text/plain"])

            json, server = RTS.run_notebook(qmd)
            RTS.validate_notebook(json)
            @test first_output(json, 2) == "42"
            @test first_output(json, 4) == "1"

            # Re-render: same warm process, fresh notebook module.
            buffer = IOBuffer()
            QNR.run!(server, qmd; output = buffer, showprogress = false)
            seekstart(buffer)
            json = RTS.JSON3.read(buffer, Any)
            @test first_output(json, 2) == "42"
            @test first_output(json, 4) == "2"

            # Closing the runner disconnects but does not kill the session.
            QNR.close!(server)
            @test process_running(proc)

            # A fresh runner re-attaches to the same session.
            json, server = RTS.run_notebook(qmd)
            @test first_output(json, 4) == "3"
            QNR.close!(server)
        end
    finally
        kill(proc)
    end
end

@testitem "attach_without_session_errors" tags = [:attach] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    dir = mktempdir()
    qmd = joinpath(dir, "attach.qmd")
    write(
        qmd,
        """
        ---
        julia:
          attach: true
        ---

        ```{julia}
        1 + 1
        ```
        """,
    )

    # An empty registry: no session to attach to.
    withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => mktempdir()) do
        server = QNR.Server()
        @test_throws QNR.UserError QNR.run!(server, qmd; showprogress = false)
        QNR.close!(server)
    end
end
