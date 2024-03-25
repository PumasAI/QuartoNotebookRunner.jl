include("../utilities/prelude.jl")

@testset "png metadata" begin
    @test QuartoNotebookRunner.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "10x15.png")),
    ) == (; width = 10, height = 15)
    @test QuartoNotebookRunner.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "15x10.png")),
    ) == (; width = 15, height = 10)
end
