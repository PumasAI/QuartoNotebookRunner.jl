@testset "concurrent run and close" begin
    s = Server()
    file = joinpath(@__DIR__, "..", "examples", "soft_scope.qmd")

    @test_nowarn @sync begin
        for i = 1:20
            Threads.@spawn begin
                run!(s, file; showprogress = false)
                # files may be closed already by another task, that's ok
                close!(s, file)
            end
        end
    end

    @test isempty(s.workers)
end
