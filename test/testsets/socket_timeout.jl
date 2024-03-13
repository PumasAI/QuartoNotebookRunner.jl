include("../utilities/prelude.jl")

using Sockets

@testset "Socket timeout" begin
    server = QuartoNotebookRunner.serve(; timeout = 1)
    sock = Sockets.connect(server.port)

    JSON3.write(sock, Dict(:type => "isready", :content => Dict()))
    println(sock)
    @test readline(sock) == "true"

    t1 = time()
    JSON3.write(
        sock,
        Dict(
            :type => "run",
            :content => abspath(joinpath(@__DIR__, "..", "examples", "sleep_3.qmd")),
        ),
    )
    println(sock)

    # check that the server stays alive during a 3 second long command, even if in the meantime
    # shorter-lived commands are completed and the server timeout is only 1 second
    sock_2 = Sockets.connect(server.port)
    JSON3.write(sock_2, Dict(:type => "isready", :content => Dict()))
    println(sock_2)
    @test readline(sock_2) == "true"

    # now we wait for the longer command to complete
    @test !isempty(readline(sock))
    t2 = time()
    @test t2 - t1 > 3

    # after the three seconds rendering time, the server should time out after a second
    wait(server)
end
