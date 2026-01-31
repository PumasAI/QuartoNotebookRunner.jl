@testitem "png metadata" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    @test QNR.png_image_metadata(read(joinpath(@__DIR__, "..", "assets", "10x15.png"))) ==
          (; width = 10, height = 15)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "10x15.png"));
        phys_correction = false,
    ) == (; width = 10, height = 15)

    @test QNR.png_image_metadata(read(joinpath(@__DIR__, "..", "assets", "15x10.png"))) ==
          (; width = 15, height = 10)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "15x10.png"));
        phys_correction = false,
    ) == (; width = 15, height = 10)

    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_no_dpi.png")),
    ) == (; width = 100, height = 100)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_no_dpi.png"));
        phys_correction = false,
    ) == (; width = 100, height = 100)

    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_96_dpi.png")),
    ) == (; width = 100, height = 100)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_96_dpi.png"));
        phys_correction = false,
    ) == (; width = 100, height = 100)

    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_300_dpi.png")),
    ) == (; width = 32, height = 32)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_300_dpi.png"));
        phys_correction = false,
    ) == (; width = 100, height = 100)

    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_600_dpi.png")),
    ) == (; width = 16, height = 16)
    @test QNR.png_image_metadata(
        read(joinpath(@__DIR__, "..", "assets", "black_600_dpi.png"));
        phys_correction = false,
    ) == (; width = 100, height = 100)
end
