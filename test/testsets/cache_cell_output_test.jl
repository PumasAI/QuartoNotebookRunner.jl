@testitem "cache-cell-output" tags = [:notebook] setup = [RunnerTestSetup] begin
    import QuartoNotebookRunner as QNR
    import .RunnerTestSetup as RTS

    let cached_cell_output = Ref{String}("")
        notebook_file = joinpath(@__DIR__, "..", "examples", "cache-cell-output.qmd")
        # First make sure that there isn't a cache folder from a previous test runs.
        cache = joinpath(dirname(notebook_file), ".cache")
        isdir(cache) && rm(cache; recursive = true)

        json, server = RTS.run_notebook(notebook_file)
        RTS.validate_notebook(json)
        cells = json["cells"]
        @test length(cells) == 3
        cell = cells[2]
        cached_cell_output[] = cell["outputs"][1]["data"]["text/plain"]
        QNR.close!(server, notebook_file)

        for _ = 1:2
            json, server = RTS.run_notebook(notebook_file)
            RTS.validate_notebook(json)
            cells = json["cells"]
            @test length(cells) == 3
            cell = cells[2]
            @test cached_cell_output[] == cell["outputs"][1]["data"]["text/plain"]
            QNR.close!(server, notebook_file)
        end

        # Then disable caching and ensure that the values are different on each run.
        disable_cache = Dict{String,Any}(
            "format" =>
                Dict{String,Any}("execute" => Dict{String,Any}("cache" => false)),
        )
        let non_cached_cell_output = Ref{String}("")
            json, server = RTS.run_notebook(notebook_file; options = disable_cache)
            RTS.validate_notebook(json)
            cells = json["cells"]
            @test length(cells) == 3
            cell = cells[2]
            non_cached_cell_output[] = cell["outputs"][1]["data"]["text/plain"]
            QNR.close!(server, notebook_file)

            for _ = 1:2
                json, server = RTS.run_notebook(notebook_file; options = disable_cache)
                RTS.validate_notebook(json)
                cells = json["cells"]
                @test length(cells) == 3
                cell = cells[2]
                @test non_cached_cell_output[] != cell["outputs"][1]["data"]["text/plain"]
                QNR.close!(server, notebook_file)
            end
        end
    end
end
