include("utilities/prelude.jl")
include("utilities/project_precompile.jl")
include("utilities/cleanup.jl")

@testset "QuartoNotebookRunner" begin
    for (root, dirs, files) in walkdir(joinpath(@__DIR__, "testsets"))
        for each in files
            _, ext = splitext(each)
            if ext == ".jl"
                include(joinpath(root, each))
            end
        end
    end
end
