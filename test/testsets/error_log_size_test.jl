@testitem "Notebook errors are not echoed to the server log" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import Logging

    # Quarto redirects the server's stderr into a blocking pipe that it drains
    # once a second, so a log record larger than the pipe buffer wedges the
    # server. Notebook errors reach the client over the socket instead.
    traceback = repeat("x", 100_000)
    error = QNR.EvaluationError([
        (kind = :error, file = "a.qmd", traceback),
        (kind = :error, file = "b.qmd", traceback),
    ])

    # `ConsoleLogger` is what the server's stderr goes through in production, and
    # it is the logger that renders an `exception` keyword as a stacktrace.
    io = IOBuffer()
    result = Logging.with_logger(Logging.ConsoleLogger(io)) do
        QNR._log_error("Failed to run notebook: notebook.qmd", error, backtrace())
    end
    logged = String(take!(io))

    @test occursin(traceback, result.juliaError)
    @test !occursin(traceback, logged)
    @test length(logged) < 16384

    # What the log keeps: the number of notebook errors, and the server-side
    # backtrace, which the client never receives and which the call depth bounds.
    @test occursin("2 notebook errors reported to the client, not logged", logged)
    @test occursin("Stacktrace:", logged)
    @test occursin("socket.jl", logged)
end
