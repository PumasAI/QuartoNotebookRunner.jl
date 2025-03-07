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
        @test length(d2["notebook"]["cells"]) == 9

        d3 = json(`$node $client $(server.port) $(server.key) isopen $(cell_types)`)
        @test d3 == true

        t_before_run = Dates.now()
        d4 = json(`$node $client $(server.port) $(server.key) run $(cell_types)`)
        t_after_run = Dates.now()
        @test d2 == d4

        d5 = json(`$node $client $(server.port) $(server.key) status`)
        @test d5 isa String
        @test occursin("workers active: 1", d5)
        @test occursin(abspath(cell_types), d5)

        d6 = json(`$node $client $(server.port) $(server.key) close $(cell_types)`)
        @test d6["status"] == true

        d7 = json(`$node $client $(server.port) $(server.key) isopen $(cell_types)`)
        @test d7 == false

        d8 = json(`$node $client $(server.port) $(server.key) run $(cell_types)`)
        @test d2 == d8

        run(`$node $client $(server.port) $(server.key) stop`)

        wait(server)
    end
end
