@testitem "DiagnosticLogger formatting" begin
    import QuartoNotebookRunner as QNR

    mktempdir() do tmpdir
        logger = QNR.DiagnosticLogger(tmpdir, "test")
        logfile = joinpath(tmpdir, "test-$(getpid()).log")

        # Basic message
        QNR.Logging.handle_message(
            logger,
            QNR.Logging.Debug,
            "hello world",
            @__MODULE__,
            :test,
            :test_id,
            @__FILE__,
            @__LINE__,
        )
        output = read(logfile, String)
        @test occursin(r"\d{2}:\d{2}:\d{2}\.\d{3}", output)
        @test occursin("[DEBUG]", output)
        @test occursin("test: hello world", output)

        # Kwargs
        QNR.Logging.handle_message(
            logger,
            QNR.Logging.Info,
            "with kwargs",
            @__MODULE__,
            :test,
            :test_id,
            @__FILE__,
            @__LINE__;
            key = "value",
            count = 42,
        )
        output = read(logfile, String)
        @test occursin("[INFO]", output)
        @test occursin("key=\"value\"", output)
        @test occursin("count=42", output)

        # Exception tuple
        bt = backtrace()
        QNR.Logging.handle_message(
            logger,
            QNR.Logging.Error,
            "failure",
            @__MODULE__,
            :test,
            :test_id,
            @__FILE__,
            @__LINE__;
            exception = (ErrorException("boom"), bt),
        )
        output = read(logfile, String)
        @test occursin("[ERROR]", output)
        @test occursin("exception = ", output)
        @test occursin("boom", output)
    end
end

@testitem "with_diagnostic_logger env gating" begin
    import QuartoNotebookRunner as QNR

    # When set: log file created with message
    mktempdir() do tmpdir
        result = withenv("QUARTONOTEBOOKRUNNER_LOG" => tmpdir) do
            QNR.with_diagnostic_logger(; prefix = "host") do
                QNR.Logging.@debug "test message"
                42
            end
        end
        @test result == 42
        logfile = joinpath(tmpdir, "host-$(getpid()).log")
        @test isfile(logfile)
        content = read(logfile, String)
        @test occursin("test message", content)
    end

    # When unset: no files, function still returns
    mktempdir() do tmpdir
        result = withenv("QUARTONOTEBOOKRUNNER_LOG" => nothing) do
            QNR.with_diagnostic_logger(; prefix = "host") do
                99
            end
        end
        @test result == 99
        @test isempty(readdir(tmpdir))
    end
end

@testitem "diagnostic logging integration" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR
    import JSON3

    mktempdir() do tmpdir
        withenv("QUARTONOTEBOOKRUNNER_LOG" => tmpdir) do
            json, server = QNR.with_diagnostic_logger(; prefix = "host") do
                server = QNR.Server()
                buffer = IOBuffer()
                QNR.run!(
                    server,
                    joinpath(@__DIR__, "..", "examples", "cell_options.qmd");
                    output = buffer,
                    showprogress = false,
                )
                json = JSON3.read(seekstart(buffer), Any)
                json, server
            end

            QNR.with_diagnostic_logger(; prefix = "host") do
                QNR.close!(server)
            end
        end

        host_logs = filter(f -> startswith(f, "host-"), readdir(tmpdir))
        worker_logs = filter(f -> startswith(f, "worker-"), readdir(tmpdir))

        @test length(host_logs) == 1
        @test length(worker_logs) == 1

        host_content = read(joinpath(tmpdir, only(host_logs)), String)
        @test occursin("run!", host_content)
        @test occursin("close!", host_content)

        worker_content = read(joinpath(tmpdir, only(worker_logs)), String)
        @test occursin("NotebookInit", worker_content)
        @test occursin("Render", worker_content)
        @test occursin("Received shutdown", worker_content)
    end
end
