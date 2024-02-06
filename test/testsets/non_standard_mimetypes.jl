include("../utilities/prelude.jl")

@testset "non-standard mime types" begin
    mktempdir() do dir
        server = QuartoNotebookRunner.Server()
        expected = Dict("typst" => "```{=typst}", "docx" => "```{=openxml}")

        env = joinpath(dir, "integrations", "CairoMakie")
        mkpath(env)
        cp(joinpath(@__DIR__, "../examples/integrations/CairoMakie"), env; force = true)

        for (format, ext) in ("typst" => "pdf", "docx" => "docx")
            cd(dir) do
                source = joinpath(@__DIR__, "../examples/$(format)_mimetypes.qmd")
                content = read(source, String)
                write("$(format)_mimetypes.qmd", content)
                ipynb = "$(format)_mimetypes.ipynb"
                QuartoNotebookRunner.run!(
                    server,
                    "$(format)_mimetypes.qmd";
                    output = ipynb,
                    showprogress = false,
                    options = Dict{String,Any}(
                        "format" => Dict("pandoc" => Dict("to" => format)),
                    ),
                )

                json = JSON3.read(ipynb)
                markdown = json.cells[end].outputs[1].data["text/markdown"]
                @test contains(markdown, expected[format])

                if !Sys.iswindows()
                    # No macOS ARM build, so just look for a local version that the dev
                    # should have installed. This avoids having to use rosetta2 to run
                    # the x86_64 version of Julia to get access to the x86_64 version of
                    # Quarto artifact.
                    quarto_bin =
                        quarto_jll.is_available() ? quarto_jll.quarto() : setenv(`quarto`)
                    # Just a smoke test to make sure it runs. Use docx since it doesn't
                    # output a bunch of folders (html), or require a tinytex install
                    # (pdf). All we are doing here at the moment is ensuring quarto doesn't
                    # break on our notebook outputs.
                    if success(`$quarto_bin --version`)
                        @test success(`$quarto_bin render $ipynb --to $format`)
                    else
                        @error "quarto not found, skipping smoke test."
                    end
                    @test isfile("$(format)_mimetypes.$ext")
                end
            end
        end
        close!(server)
    end
end
