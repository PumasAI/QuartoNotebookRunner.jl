include("../../utilities/prelude.jl")

@testset "quarto includes" begin
    file =
        joinpath(@__DIR__, "..", "..", "examples", "quarto_integration", "with_include.qmd")
    # TODO: use quarto_jll for integration tests once modern enough versions are available
    cmd = addenv(
        `quarto render $file --to md`,
        "QUARTO_JULIA_PROJECT" => normpath(joinpath(@__DIR__, "..", "..", "..")),
    )
    run(cmd)
    outputfile =
        joinpath(@__DIR__, "..", "..", "examples", "quarto_integration", "with_include.md")
    @test occursin("y = 2", read(outputfile, String))
    rm(outputfile)
end
