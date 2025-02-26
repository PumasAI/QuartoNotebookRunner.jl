include("../utilities/prelude.jl")

@testset "package integration hooks" begin
    mktempdir() do dir
        env_dir = joinpath(@__DIR__, "../examples/integrations/CairoMakie")
        content =
            read(joinpath(@__DIR__, "../examples/integrations/CairoMakie.qmd"), String)
        cd(dir) do
            server = QuartoNotebookRunner.Server()

            cp(env_dir, joinpath(dir, "CairoMakie"))

            function png_metadata(preamble = nothing)
                # handle Windows
                content_unified = replace(content, "\r\n" => "\n")
                _content =
                    preamble === nothing ? content_unified :
                    replace(content_unified, """
                fig-width: 4
                fig-height: 3
                fig-dpi: 150""" => preamble)

                write("CairoMakie.qmd", _content)
                json = QuartoNotebookRunner.run!(
                    server,
                    "CairoMakie.qmd";
                    showprogress = false,
                )
                return json.cells[end-1].outputs[1].metadata["image/png"]
            end

            metadata = png_metadata()
            @test metadata.width == 4 * 150
            @test metadata.height == 3 * 150

            metadata = png_metadata("""
                fig-width: 8
                fig-height: 6
                fig-dpi: 300""")
            @test metadata.width == 8 * 300
            @test metadata.height == 6 * 300

            metadata = png_metadata("""
                fig-width: 5
                fig-dpi: 100""")
            @test metadata.width == 5 * 100
            @test metadata.height == round(5 / 4 * 3 * 100)

            metadata = png_metadata("""
                fig-height: 5
                fig-dpi: 100""")
            @test metadata.height == 5 * 100
            @test metadata.width == round(5 / 3 * 4 * 100)

            # we don't want to rely on hardcoding Makie's own default size for our tests
            # but for the dpi-only test we can check that doubling the
            # dpi doubles image dimensions, whatever they are
            metadata_100dpi = png_metadata("""
                fig-dpi: 96""")
            metadata_200dpi = png_metadata("""
                fig-dpi: 192""")
            @test 2 * metadata_100dpi.height == metadata_200dpi.height
            @test 2 * metadata_100dpi.width == metadata_200dpi.width

            # same logic for width and height only
            metadata_single = png_metadata("""
                fig-width: 3
                fig-height: 2""")
            metadata_double = png_metadata("""
                fig-width: 6
                fig-height: 4""")
            @test 2 * metadata_single.height == metadata_double.height
            @test 2 * metadata_single.width == metadata_double.width

            close!(server)
        end
    end
end
