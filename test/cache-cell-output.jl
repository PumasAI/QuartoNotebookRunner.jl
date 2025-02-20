include("../utilities/prelude.jl")

# Run the notebook twice and confirm that the `rand()` value output from the
# cell is the same both times, since it is cached to `.cache` folder.
let cached_cell_output = Ref{String}("")
    notebook_file = joinpath(@__DIR__, "../examples/cache-cell-output.qmd")
    # First make sure that there isn't a cache folder from a previous test runs.
    cache = joinpath(dirname(notebook_file), ".cache")
    isdir(cache) && rm(cache; recursive = true)
    test_example(notebook_file) do json
        cells = json["cells"]
        @test length(cells) == 3
        cached_cell_output[] = cell["outputs"][1]["text"]
    end
    test_example(notebook_file) do json
        cells = json["cells"]
        @test length(cells) == 3
        @test cached_cell_output[] == cell["outputs"][1]["text"]
    end
    test_example(notebook_file) do json
        cells = json["cells"]
        @test length(cells) == 3
        @test cached_cell_output[] == cell["outputs"][1]["text"]
    end
    disable_cache = Dict{String,Any}(
        "format" => Dict{String,Any}(
            "metadata" => Dict{String,Any}(
                "julia" => Dict{String,Any}("cache-cell-output" => false),
            ),
        ),
    )
    let non_cached_cell_output = Ref{String}("")
        test_example(notebook_file, disable_cache) do json
            cells = json["cells"]
            @test length(cells) == 3
            non_cached_cell_output[] = cell["outputs"][1]["text"]
        end
        test_example(notebook_file, disable_cache) do json
            cells = json["cells"]
            @test length(cells) == 3
            @test non_cached_cell_output[] != cell["outputs"][1]["text"]
        end
    end
end
