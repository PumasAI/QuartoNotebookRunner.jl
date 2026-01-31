@testitem "HMAC signing" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import Sockets
    import Logging

    function eof_or_econnreset(socket)
        try
            eof(socket)
        catch err
            if !(err isa Base.IOError && err.code == Base.UV_ECONNRESET)
                rethrow(err)
            end
            true
        end
    end

    @info "Running HMAC signing test"
    test_logger = Test.TestLogger()
    Logging.with_logger(test_logger) do
        server = QNR.serve()
        sock = Sockets.connect(server.port)

        wrong_key = Base.UUID(1234)

        command = Dict(
            :type => "run",
            :content =>
                abspath(joinpath(@__DIR__, "..", "examples", "cell_options.qmd")),
        )

        # check that an error is returned and no document has been run if the key is wrong
        QNR._write_hmac_json(sock, wrong_key, command)
        @test occursin("Incorrect HMAC digest", readline(sock))
        @test eof_or_econnreset(sock) # server closes upon receiving wrong hmac

        # reconnect
        sock = Sockets.connect(server.port)
        @test lock(server.notebookserver.lock) do
            isempty(server.notebookserver.workers)
        end

        # and that the opposite holds if the key is right
        QNR._write_hmac_json(sock, server.key, command)
        @test !occursin("Incorrect HMAC digest", readline(sock))
        @test lock(server.notebookserver.lock) do
            length(server.notebookserver.workers) == 1
        end

        QNR._write_hmac_json(sock, server.key, Dict(:type => "stop", :content => Dict()))

        wait(server)
    end
    @test any(r -> r.message == "Incorrect HMAC digest", test_logger.logs)
end
