@testitem "cache manifest invalidation" tags = [:notebook] setup = [RunnerTestSetup] begin
    import QuartoNotebookRunner as QNR
    import .RunnerTestSetup as RTS

    import Pkg

    mktempdir() do dir
        # Empty project environment, resolved to get a valid Manifest.toml.
        write(joinpath(dir, "Project.toml"), "[deps]\n")
        Pkg.activate(Pkg.resolve, dir)

        notebook = joinpath(dir, "cached.qmd")
        write(
            notebook,
            """
            ---
            title: Manifest cache test
            engine: julia
            execute:
                cache: true
            julia:
                exeflags: ["--color=no"]
            ---

            ```{julia}
            time_ns()
            ```
            """,
        )

        cache_dir = joinpath(dir, ".cache")
        isdir(cache_dir) && rm(cache_dir; recursive = true)

        # First run: populate cache.
        json1, server1 = RTS.run_notebook(notebook)
        output1 = json1["cells"][2]["outputs"][1]["data"]["text/plain"]
        QNR.close!(server1, notebook)

        # Second run: cache hit, same output.
        json2, server2 = RTS.run_notebook(notebook)
        output2 = json2["cells"][2]["outputs"][1]["data"]["text/plain"]
        QNR.close!(server2, notebook)
        @test output1 == output2

        # Modify Manifest.toml content without changing Project.toml.
        manifest_path = joinpath(dir, "Manifest.toml")
        open(manifest_path, "a") do io
            println(io, "# extra content to change the hash")
        end

        # Third run: manifest changed, cache must miss, new output.
        json3, server3 = RTS.run_notebook(notebook)
        output3 = json3["cells"][2]["outputs"][1]["data"]["text/plain"]
        QNR.close!(server3, notebook)
        @test output1 != output3
    end
end
