include("../../utilities/prelude.jl")

@testset "socket server" begin
    cd(@__DIR__) do
        node = NodeJS_18_jll.node()
        client = joinpath(@__DIR__, "client.js")
        port = 4001
        server = QuartoNotebookRunner.serve(; port, showprogress = false)
        sleep(1)
        json(cmd) = JSON3.read(read(cmd, String), Any)

        cell_types = "../../examples/cell_types.qmd"

        d1 = json(`$node $client $port run $(cell_types)`)
        @test length(d1["notebook"]["cells"]) == 6

        d2 = json(`$node $client $port run $(cell_types)`)
        @test d1 == d2

        d3 = json(`$node $client $port close $(cell_types)`)
        @test d3["status"] == true

        d4 = json(`$node $client $port run $(cell_types)`)
        @test d1 == d4

        d5 = json(`$node $client $port stop`)
        @test d5["message"] == "Server stopped."

        wait(server)
    end
end
