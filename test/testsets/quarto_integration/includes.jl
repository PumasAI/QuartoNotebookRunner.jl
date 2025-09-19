include("../../utilities/prelude.jl")

@testset "quarto includes" begin
    dir = joinpath(@__DIR__, "..", "..", "examples", "quarto_integration")
    # the quarto project is not recognized by quarto within the test folder
    # structure for some reason, so we move it out into a temp directory
    mktempdir() do tmpdir
        cp(dir, tmpdir; force = true)

        file = joinpath(tmpdir, "subfolder", "with_include.qmd")
        # TODO: use quarto_jll for integration tests once modern enough versions are available
        cmd = addenv(
            `quarto render $file --to md`,
            "QUARTO_JULIA_PROJECT" => normpath(joinpath(@__DIR__, "..", "..", "..")),
        )
        run(cmd)
        outputfile = joinpath(tmpdir, "subfolder", "with_include.md")

        str = read(outputfile, String)

        @test occursin("INCLUDE A", str)
        @test occursin(joinpath(tmpdir, "subfolder", "to_include_A.qmd:3"), str)
        @test occursin("INCLUDE B", str)
        @test occursin(
            joinpath(tmpdir, "subfolder", "include_subfolder", "to_include_B.qmd:6"),
            str,
        )
        @test occursin("INCLUDE C", str)
        @test occursin(joinpath(tmpdir, "to_include_C.qmd:4"), str)
        @test occursin("D = 6", str)
    end
end
