include("../../utilities/prelude.jl")

@testset "socket server" begin
    cd(@__DIR__) do
        node = NodeJS_18_jll.node()
        client = joinpath(@__DIR__, "client.js")
        server = QuartoNotebookRunner.serve(; showprogress = false)
        sleep(1)
        json(cmd) = JSON3.read(read(cmd, String), Any)

        cell_types = abspath("../../examples/cell_types.qmd")

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

        # test that certain commands on notebooks fail while those notebooks are already running

        sleep_10 = abspath("../../examples/sleep_10.qmd")
        sleep_task = Threads.@spawn json(
            `$node $client $(server.port) $(server.key) run $(sleep_10)`,
        )

        # wait until server lock locks due to the `run` command above
        while !islocked(server.notebookserver.lock)
            sleep(0.001)
        end
        # wait just until the previous task releases the server lock, which is when it has
        # attained the lock for the new file
        lock(server.notebookserver.lock) do
        end

        # both of these tasks should then try to access the worker that is busy and fail because
        # the lock is already held
        d9_task = Threads.@spawn redirect_stderr(devnull) do
            json(`$node $client $(server.port) $(server.key) run $(sleep_10)`)
        end
        d10_task = Threads.@spawn redirect_stderr(devnull) do
            json(`$node $client $(server.port) $(server.key) close $(sleep_10)`)
        end

        d9 = fetch(d9_task)
        @test occursin("the corresponding worker is busy", d9["juliaError"])

        d10 = fetch(d10_task)
        @test occursin("the corresponding worker is busy", d10["juliaError"])

        d11 = fetch(sleep_task)
        @test haskey(d11, "notebook")

        run(`$node $client $(server.port) $(server.key) stop`)

        wait(server)
    end
end
