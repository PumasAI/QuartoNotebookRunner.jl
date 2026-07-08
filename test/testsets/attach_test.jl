@testsnippet AttachSession begin
    # Launch a live session serving the worker protocol in a separate process,
    # standing in for a user's REPL. QuartoNotebookWorker resolves from its
    # package directory on the LOAD_PATH; its dependencies are stdlibs. The
    # session defines `ATTACH_MARKER`/`ATTACH_COUNTER` in its `Main` so renders
    # can prove they reached its state. Returns the process, already past the
    # `ATTACH_PORT=` handshake.
    function start_attach_session(dir, registry)
        worker_pkg =
            normpath(joinpath(dirname(@__DIR__), "..", "src", "QuartoNotebookWorker"))
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
        port_line = readline(proc)
        @assert startswith(port_line, "ATTACH_PORT=") port_line
        return proc
    end

    # The session announces renders with `printstyled`, so under forced color
    # the line arrives wrapped in ANSI escapes. Strip them to assert on text.
    strip_ansi(s) = replace(s, r"\e\[[0-9;]*m" => "")
end

@testitem "attach_to_live_session" tags = [:attach] setup = [RunnerTestSetup, AttachSession] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    registry = mktempdir()
    dir = mktempdir()
    qmd = joinpath(dir, "attach.qmd")
    write(
        qmd,
        """
        ---
        title: attach
        ---

        ```{julia}
        Main.ATTACH_MARKER
        ```

        ```{julia}
        Main.ATTACH_COUNTER[] += 1
        ```
        """,
    )

    proc = start_attach_session(dir, registry)

    try
        withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry) do
            first_output(json, nth) =
                join(json["cells"][nth]["outputs"][1]["data"]["text/plain"])

            # No `attach` in the frontmatter: attachment follows from a live
            # session serving the notebook's root.
            json, server = RTS.run_notebook(qmd)
            RTS.validate_notebook(json)
            @test first_output(json, 2) == "42"
            @test first_output(json, 4) == "1"

            # The session announces each render it absorbs.
            log_line = strip_ansi(readline(proc))
            @test startswith(log_line, "attached render:")
            @test occursin("attach.qmd", log_line)

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

@testitem "attach_announces_once_per_render" tags = [:attach] setup =
    [RunnerTestSetup, AttachSession] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    registry = mktempdir()
    dir = mktempdir()
    qmd = joinpath(dir, "once.qmd")
    write(qmd, "---\ntitle: once\n---\n\n```{julia}\n1 + 1\n```\n")

    proc = start_attach_session(dir, registry)

    try
        withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry) do
            # A render announces itself exactly once. Both prints in a doubled
            # render flush before `run!` returns, so any second line is already
            # buffered on the pipe after the first is drained.
            _, server = RTS.run_notebook(qmd)
            line = strip_ansi(readline(proc))
            @test startswith(line, "attached render:")
            @test occursin("once.qmd", line)
            sleep(0.5)
            @test bytesavailable(proc) == 0

            QNR.close!(server)
        end
    finally
        kill(proc)
    end
end

@testitem "attach_serves_multiple_notebooks" tags = [:attach] setup =
    [RunnerTestSetup, AttachSession] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    registry = mktempdir()
    dir = mktempdir()
    cell = "```{julia}\nMain.ATTACH_MARKER\n```\n"
    a = joinpath(dir, "a.qmd")
    b = joinpath(dir, "b.qmd")
    write(a, "---\ntitle: a\n---\n\n$cell")
    write(b, "---\ntitle: b\n---\n\n$cell")

    proc = start_attach_session(dir, registry)

    try
        withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry) do
            marker(json) = join(json["cells"][2]["outputs"][1]["data"]["text/plain"])

            # Each notebook holds its own connection to the session. Before the
            # session accepted connections concurrently, opening the second one
            # deadlocked the runner in the attach handshake. Both reach the same
            # `Main.ATTACH_MARKER`, proving they share the one live process.
            json, server = RTS.run_notebook(a)
            @test marker(json) == "42"

            buffer = IOBuffer()
            QNR.run!(server, b; output = buffer, showprogress = false)
            seekstart(buffer)
            @test marker(RTS.JSON3.read(buffer, Any)) == "42"

            QNR.close!(server)
        end
    finally
        kill(proc)
    end
end

@testitem "attach_opt_out_forces_spawn" tags = [:attach] setup =
    [RunnerTestSetup, AttachSession] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    registry = mktempdir()
    dir = mktempdir()
    qmd = joinpath(dir, "optout.qmd")
    write(
        qmd,
        """
        ---
        title: optout
        ---

        ```{julia}
        isdefined(Main, :ATTACH_MARKER)
        ```
        """,
    )

    proc = start_attach_session(dir, registry)

    try
        # A session is serving this root, but the opt-out forces a spawned
        # worker whose fresh `Main` has no `ATTACH_MARKER`.
        withenv(
            "QUARTONOTEBOOKRUNNER_ATTACH_DIR" => registry,
            "QUARTONOTEBOOKRUNNER_NO_ATTACH" => "true",
        ) do
            first_output(json, nth) =
                join(json["cells"][nth]["outputs"][1]["data"]["text/plain"])
            json, server = RTS.run_notebook(qmd)
            @test first_output(json, 2) == "false"
            QNR.close!(server)
        end
    finally
        kill(proc)
    end
end

@testitem "render_without_session_spawns" tags = [:attach] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    dir = mktempdir()
    qmd = joinpath(dir, "plain.qmd")
    write(
        qmd,
        """
        ---
        title: plain
        ---

        ```{julia}
        1 + 1
        ```
        """,
    )

    # An empty registry: no session serves the root, so the render spawns a
    # worker instead of erroring.
    withenv("QUARTONOTEBOOKRUNNER_ATTACH_DIR" => mktempdir()) do
        first_output(json, nth) =
            join(json["cells"][nth]["outputs"][1]["data"]["text/plain"])
        json, server = RTS.run_notebook(qmd)
        @test first_output(json, 2) == "2"
        QNR.close!(server)
    end
end
