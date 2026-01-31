@testitem "Socket timeout" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import Sockets

    @info "Running socket timeout test"
    server = QNR.serve(; timeout = 2)
    sock = Sockets.connect(server.port)

    QNR._write_hmac_json(sock, server.key, Dict(:type => "isready", :content => Dict()))
    @test readline(sock) == "true"

    sleep_qmd = abspath(joinpath(@__DIR__, "..", "examples", "sleep_3.qmd"))

    t1 = time()
    QNR._write_hmac_json(sock, server.key, Dict(:type => "run", :content => sleep_qmd))
    @test occursin("progress_update", readline(sock))
    @test !isempty(readline(sock))
    t2 = time()
    @test t2 - t1 >= 3

    QNR._write_hmac_json(sock, server.key, Dict(:type => "close", :content => sleep_qmd))
    @test !isempty(readline(sock))

    # after the three seconds rendering time, the server should time out after two seconds
    wait(server)
    t3 = time()
    @test t3 > 2
end
