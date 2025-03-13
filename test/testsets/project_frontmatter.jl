include("../utilities/prelude.jl")

@testset "project frontmatter" begin
    mktempdir() do dir
        content = read(joinpath(@__DIR__, "../examples/mimetypes.qmd"), String)
        cd(dir) do
            cp(joinpath(@__DIR__, "../examples/mimetypes"), joinpath(dir, "mimetypes"))
            server = QuartoNotebookRunner.Server()
            write("mimetypes.qmd", content)
            options = Dict{String,Any}(
                "format" =>
                    Dict{String,Any}("execute" => Dict{String,Any}("fig-dpi" => 100)),
            )
            json = QuartoNotebookRunner.run!(
                server,
                "mimetypes.qmd";
                options,
                showprogress = false,
            )
            cell = json.cells[6]
            metadata = cell.outputs[1].metadata["image/png"]
            pngbytes = Base64.base64decode(cell.outputs[1].data["image/png"])
            px_size = QuartoNotebookRunner.png_image_metadata(
                pngbytes;
                phys_correction = false,
            )
            @test metadata.width == 600
            @test metadata.height == 450
            @test px_size.width == 625
            @test px_size.height == 469

            options_file = "temp_options.json"
            open(options_file, "w") do io
                JSON3.pretty(io, options)
            end

            json = QuartoNotebookRunner.run!(
                server,
                "mimetypes.qmd";
                options = options_file,
                showprogress = false,
            )
            cell = json.cells[6]
            metadata = cell.outputs[1].metadata["image/png"]
            pngbytes = Base64.base64decode(cell.outputs[1].data["image/png"])
            px_size = QuartoNotebookRunner.png_image_metadata(
                pngbytes;
                phys_correction = false,
            )
            @test metadata.width == 600
            @test metadata.height == 450
            @test px_size.width == 625
            @test px_size.height == 469

            close!(server)
        end
    end
end
