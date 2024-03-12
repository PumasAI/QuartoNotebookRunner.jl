@testset "concurrent run and close" begin
    s = Server()
    file = joinpath(@__DIR__, "..", "examples", "soft_scope.qmd")

    @test_nowarn @sync begin
        for i in 1:20
            Threads.@spawn begin
                run!(s, file)
                try
                    # files may be closed already by another task, that's ok
                    close!(s, file)
                catch e
                    if !(e isa QuartoNotebookRunner.NoFileEntryError)
                        # unexpected
                        rethrow(e)
                    end
                end
            end
        end
    end
end