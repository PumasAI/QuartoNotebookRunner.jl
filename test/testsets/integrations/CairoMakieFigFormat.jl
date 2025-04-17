include("../../utilities/prelude.jl")


@testset "CairoMakie fig-formats" begin
    s = read(
        joinpath(@__DIR__, "../../examples/integrations/CairoMakieFigFormat.qmd"),
        String,
    )

    env = abspath(joinpath(@__DIR__, "../../examples/integrations/CairoMakie/Project.toml"))

    showable_mimes(::Union{Val{:png},Val{:jpeg},Val{:retina}}) = ["image/png", "text/html"]
    showable_mimes(::Union{Val{:pdf},Val{:svg}}) = ["image/svg+xml", "application/pdf"]
    not_showable_mimes(::Union{Val{:png},Val{:jpeg},Val{:retina}}) =
        showable_mimes(Val(:pdf))
    not_showable_mimes(::Union{Val{:pdf},Val{:svg}}) = ["text/html"] # png stays as a fallback that should not be chosen if svg or pdf are accepted

    mktempdir() do dir
        server = QuartoNotebookRunner.Server()
        file = joinpath(dir, "temp.qmd")

        @testset "$format" for format in [:png, :jpeg, :retina, :svg, :pdf]
            open(file, "w") do io
                print(
                    io,
                    replace(
                        s,
                        "retina" => format,
                        "CAIROMAKIE_ENV" => env,
                        "SHOWABLE_MIMES" => repr(showable_mimes(Val(format))),
                        "NOT_SHOWABLE_MIMES" => repr(not_showable_mimes(Val(format))),
                    ),
                )
            end

            result = QuartoNotebookRunner.run!(server, file)
            cells = result.cells
            println("$format\n")
            display(cells[6].outputs[1])
            println("\n")
            display(cells[8].outputs[1])
            println("\n")
            @test cells[6].outputs[1].data["text/plain"] == "true"
            @test cells[8].outputs[1].data["text/plain"] == "true"
        end

        QuartoNotebookRunner.close!(server)
    end
end
