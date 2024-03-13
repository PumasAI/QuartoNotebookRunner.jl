include("../../utilities/prelude.jl")

using Sockets

@testset "Socket timeout" begin
    node = NodeJS_18_jll.node()
    client = joinpath(@__DIR__, "client.js")
    json(cmd) = JSON3.read(read(cmd, String), Any)

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
            :content => abspath(joinpath(@__DIR__, "..", "..", "examples", "sleep_3.qmd")),
        ),
    )
    println(sock)

    # check that the server stays alive during a 3 second long command, even if in the meantime
    # shorter-lived commands are completed and the server timeout is only 1 second
    @test json(`$node $client $(server.port) isready`)

    # now we wait for the longer command to complete
    @test !isempty(readline(sock))
    t2 = time()
    @test t2 - t1 > 3

    # after the three seconds rendering time, the server should time out after a second
    wait(server)
end
