include("../utilities/prelude.jl")

@testset "manifest mismatch" begin
    # The commited manifest is for 1.8, so this test would fail on that
    # version. But none of our CI runs on that version so this is a safe
    # version to skip in this test.
    if VERSION < v"1.8" || VERSION > v"1.8"
        s = Server()
        path = joinpath(@__DIR__, "../examples/manifest_mismatch/manifest_mismatch.qmd")
        if VERSION < v"1.8"
            @test_throws ErrorException QuartoNotebookRunner.run!(s, path)
        else
            @test_throws "expected_julia_version = \"1.8.5\"" QuartoNotebookRunner.run!(
                s,
                path,
            )
        end
    end
end
