include("../utilities/prelude.jl")

# Run the notebook several times and confirm that the `time_ns()` value output
# from the cell is the same both times, since it is cached to `.cache` folder.
@testset "cache-cell-output" begin
    let cached_cell_output = Ref{String}("")
        notebook_file = joinpath(@__DIR__, "../examples/cache-cell-output.qmd")
        # First make sure that there isn't a cache folder from a previous test runs.
        cache = joinpath(dirname(notebook_file), ".cache")
        isdir(cache) && rm(cache; recursive = true)
        test_example(notebook_file) do json
            cells = json["cells"]
            @test length(cells) == 3
            cell = cells[2]
            cached_cell_output[] = cell["outputs"][1]["data"]["text/plain"]
        end
        for _ = 1:2
            test_example(notebook_file) do json
                cells = json["cells"]
                @test length(cells) == 3
                cell = cells[2]
                @test cached_cell_output[] == cell["outputs"][1]["data"]["text/plain"]
            end
        end
        # Then disable caching and ensure that the values are different on each run.
        disable_cache = Dict{String,Any}(
            "format" =>
                Dict{String,Any}("execute" => Dict{String,Any}("cache" => false)),
        )
        let non_cached_cell_output = Ref{String}("")
            test_example(notebook_file, disable_cache) do json
                cells = json["cells"]
                @test length(cells) == 3
                cell = cells[2]
                non_cached_cell_output[] = cell["outputs"][1]["data"]["text/plain"]
            end
            for _ = 1:2
                test_example(notebook_file, disable_cache) do json
                    cells = json["cells"]
                    @test length(cells) == 3
                    cell = cells[2]
                    @test non_cached_cell_output[] !=
                          cell["outputs"][1]["data"]["text/plain"]
                end
            end
        end
    end
end
