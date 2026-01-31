@testitem "socket server" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import JSON3
    import Dates
    import NodeJS_18_jll
    import Logging

    @info "Running socket server test"
    test_logger = Test.TestLogger()
    Logging.with_logger(test_logger) do
        cd(@__DIR__) do
            node = NodeJS_18_jll.node()
            client = joinpath(@__DIR__, "socket_server", "client.js")
            server = QNR.serve(; showprogress = false)
            sleep(1)
            json(cmd) = JSON3.read(read(cmd, String), Any)

            cell_types = abspath(joinpath(@__DIR__, "..", "examples", "cell_types.qmd"))

            @test json(`$node $client $(server.port) $(server.key) isready`)

            d1 = json(
                `$node $client $(server.port) $(server.key) isopen $(JSON3.write(cell_types))`,
            )
            @test d1 == false

            d2 = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(cell_types))`,
            )
            @test length(d2["notebook"]["cells"]) == 9

            d3 = json(
                `$node $client $(server.port) $(server.key) isopen $(JSON3.write(cell_types))`,
            )
            @test d3 == true

            t_before_run = Dates.now()
            d4 = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(cell_types))`,
            )
            t_after_run = Dates.now()
            @test d2 == d4

            d5 = json(`$node $client $(server.port) $(server.key) status`)
            @test d5 isa String
            @test occursin("workers active: 1", d5)
            @test occursin(abspath(cell_types), d5)

            d6 = json(
                `$node $client $(server.port) $(server.key) close $(JSON3.write(cell_types))`,
            )
            @test d6["status"] == true

            d7 = json(
                `$node $client $(server.port) $(server.key) isopen $(JSON3.write(cell_types))`,
            )
            @test d7 == false

            d8 = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(cell_types))`,
            )
            @test d2 == d8

            # test that certain commands on notebooks fail while those notebooks are already running

            sleep_10 = abspath(joinpath(@__DIR__, "..", "examples", "sleep_10.qmd"))
            sleep_task = Threads.@spawn json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(sleep_10))`,
            )

            # wait until server lock locks due to the `run` command above
            while !islocked(server.notebookserver.lock)
                sleep(0.001)
            end
            # wait just until the previous task releases the server lock, which is when it has
            # attained the lock for the new file
            lock(server.notebookserver.lock) do
            end

            # both of these tasks should then try to access the worker that is busy and fail
            d9_task = Threads.@spawn json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(sleep_10))`,
            )
            d10_task = Threads.@spawn json(
                `$node $client $(server.port) $(server.key) close $(JSON3.write(sleep_10))`,
            )

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
    @test any(r -> contains(r.message, "Failed to run notebook"), test_logger.logs)
    @test any(r -> contains(r.message, "Failed to close notebook"), test_logger.logs)
end

@testitem "socket server force close" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import JSON3
    import NodeJS_18_jll
    import Logging

    @info "Running socket server force close test"
    test_logger = Test.TestLogger()
    Logging.with_logger(test_logger) do
        cd(@__DIR__) do
            node = NodeJS_18_jll.node()
            client = joinpath(@__DIR__, "socket_server", "client.js")
            server = QNR.serve(; showprogress = false)
            sleep(1)
            json(cmd) = JSON3.read(read(cmd, String), Any)

            sleep_10 = abspath(joinpath(@__DIR__, "..", "examples", "sleep_10.qmd"))
            sleep_task = Threads.@spawn json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(sleep_10))`,
            )

            # wait until server lock locks due to the `run` command above
            while !islocked(server.notebookserver.lock)
                sleep(0.001)
            end
            # wait just until the previous task releases the server lock, which is when it has
            # attained the lock for the new file
            lock(server.notebookserver.lock) do
            end

            # force-closing should kill the worker even if it's running
            d1 = json(
                `$node $client $(server.port) $(server.key) forceclose $(JSON3.write(sleep_10))`,
            )
            @test d1 == Dict{String,Any}("status" => true)

            d2 = fetch(sleep_task)
            @test occursin("File was force-closed", d2["juliaError"])

            # check that force-closing also works when a notebook is not currently running

            cell_types = abspath(joinpath(@__DIR__, "..", "examples", "cell_types.qmd"))

            d3 = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(cell_types))`,
            )

            d4 = json(
                `$node $client $(server.port) $(server.key) forceclose $(JSON3.write(cell_types))`,
            )
            @test d4 == Dict{String,Any}("status" => true)

            run(`$node $client $(server.port) $(server.key) stop`)

            wait(server)
        end
    end
    @test any(r -> contains(r.message, "Failed to run notebook"), test_logger.logs)
end

@testitem "source ranges" tags = [:socket] begin
    import QuartoNotebookRunner as QNR
    import JSON3
    import NodeJS_18_jll
    import Logging

    @info "Running source ranges test"
    test_logger = Test.TestLogger()
    Logging.with_logger(test_logger) do
        cd(@__DIR__) do
            with_include = abspath(
                joinpath(@__DIR__, "..", "examples", "sourceranges", "with_include.qmd"),
            )
            to_include = abspath(
                joinpath(@__DIR__, "..", "examples", "sourceranges", "to_include.qmd"),
            )

            with_include_md = read(with_include, String)
            to_include_md = read(to_include, String)

            with_include_A, with_include_B =
                split(with_include_md, r"{{< include to_include\.qmd >}}\r?\n")

            lines_A = length(split(with_include_A, "\n"))
            lines_B = length(split(with_include_B, "\n"))
            lines_to_include = length(split(to_include_md, "\n"))

            # this mocks the current behavior of quarto where it sometimes inserts newlines
            # without tracking info after includes
            empty_line = ""

            full = join([with_include_A, to_include_md, empty_line, with_include_B], "\n")

            ends = cumsum([lines_A, lines_to_include, 1, lines_B])

            source_ranges = [
                (; file = with_include, lines = [1, ends[1]], sourceLines = [1, lines_A]),
                (;
                    file = to_include,
                    lines = [ends[1] + 1, ends[2]],
                    sourceLines = [1, lines_to_include],
                ),
                (;
                    # the empty lines that quarto sometimes add lack file and sourceLines
                    lines = [ends[2] + 1, ends[3]],
                ),
                (;
                    file = with_include,
                    lines = [ends[3] + 1, ends[4]],
                    sourceLines = [lines_A + 1, lines_A + lines_B],
                ),
            ]

            node = NodeJS_18_jll.node()
            client = joinpath(@__DIR__, "socket_server", "client.js")
            server = QNR.serve(; showprogress = false)
            sleep(1)
            json(cmd) = JSON3.read(read(cmd, String), Any)

            options = (; target = (; markdown = (; value = full)))

            full_lines = split(full, "\n")

            content_without_ranges = (; file = with_include, options)
            result = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(content_without_ranges))`,
            )

            first_line_with_print =
                findfirst(contains(raw"""print("$(@__FILE__):$(@__LINE__)")"""), full_lines)
            last_line_with_print =
                findlast(contains(raw"""print("$(@__FILE__):$(@__LINE__)")"""), full_lines)

            # check that the FILE/LINE printouts reflect only the concatenated (root) file
            @test result["notebook"]["cells"][2]["outputs"][1]["text"] ==
                  "$(with_include):$first_line_with_print"
            @test result["notebook"]["cells"][4]["outputs"][1]["text"] ==
                  "$(with_include):$last_line_with_print"

            content_with_ranges =
                (; file = with_include, sourceRanges = source_ranges, options)
            result = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(content_with_ranges))`,
            )

            line_in_with_include = findfirst(
                contains(raw"""print("$(@__FILE__):$(@__LINE__)")"""),
                collect(eachline(with_include)),
            )
            line_in_to_include = findfirst(
                contains(raw"""print("$(@__FILE__):$(@__LINE__)")"""),
                collect(eachline(to_include)),
            )

            # check that the FILE/LINE printouts reflect the original files and line numbers
            @test result["notebook"]["cells"][2]["outputs"][1]["text"] ==
                  "$(to_include):$line_in_to_include"
            @test result["notebook"]["cells"][4]["outputs"][1]["text"] ==
                  "$(with_include):$line_in_with_include"

            # modify one of the source line boundaries so it mismatches
            source_ranges[1].sourceLines[2] -= 1
            result = json(
                `$node $client $(server.port) $(server.key) run $(JSON3.write(content_with_ranges))`,
            )
            @test contains(
                result["juliaError"],
                "Mismatching lengths of lines 1:5 (5) and source_lines 1:4",
            )
        end
    end
    @test any(r -> contains(r.message, "Failed to run notebook"), test_logger.logs)
end
