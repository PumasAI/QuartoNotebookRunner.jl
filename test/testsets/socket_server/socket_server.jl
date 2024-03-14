include("../../utilities/prelude.jl")

@testset "socket server" begin
    cd(@__DIR__) do
        node = NodeJS_18_jll.node()
        client = joinpath(@__DIR__, "client.js")
        server = QuartoNotebookRunner.serve(; showprogress = false)
        sleep(1)
        json(cmd) = JSON3.read(read(cmd, String), Any)

        cell_types = "../../examples/cell_types.qmd"

        @test json(`$node $client $(server.port) $(server.key) isready`)

        d1 = json(`$node $client $(server.port) $(server.key) isopen $(cell_types)`)
        @test d1 == false

        d2 = json(`$node $client $(server.port) $(server.key) run $(cell_types)`)
        @test length(d2["notebook"]["cells"]) == 6

        d3 = json(`$node $client $(server.port) $(server.key) isopen $(cell_types)`)
        @test d3 == true

        d4 = json(`$node $client $(server.port) $(server.key) run $(cell_types)`)
        @test d2 == d4

        d5 = json(`$node $client $(server.port) $(server.key) close $(cell_types)`)
        @test d5["status"] == true

        d6 = json(`$node $client $(server.port) $(server.key) isopen $(cell_types)`)
        @test d6 == false

        d7 = json(`$node $client $(server.port) $(server.key) run $(cell_types)`)
        @test d2 == d7

        d8 = json(`$node $client $(server.port) $(server.key) stop`)
        @test d8["message"] == "Server stopped."

        wait(server)
    end
end
