include("../utilities/prelude.jl")

@testset "exeflags merging" begin

    function with_replacement_file(f, file, replacements...)
        s = read(file, String)
        mktempdir() do dir
            tempfile = joinpath(dir, basename(file))
            open(tempfile, "w") do io
                write(io, replace(s, replacements...))
            end
            f(tempfile)
        end
    end

    file = joinpath(@__DIR__, "../examples/exeflags_merging.qmd")

    withenv("QUARTONOTEBOOKRUNNER_EXEFLAGS" => "[\"--project=/set_via_env\", \"--threads=3\"]") do
        server = QuartoNotebookRunner.Server()
        json = QuartoNotebookRunner.run!(server, file; showprogress = false)
        @test contains(json.cells[2].outputs[1].text, "set_via_env")
        @test json.cells[4].outputs[1].text == "3"
        close!(server)

        with_replacement_file(file, "[]" => "[\"--project=/override_via_frontmatter\"]") do newfile
            server = QuartoNotebookRunner.Server()
            json = QuartoNotebookRunner.run!(server, newfile; showprogress = false)
            @test contains(json.cells[2].outputs[1].text, "override_via_frontmatter")
            @test json.cells[4].outputs[1].text == "3"
            close!(server)
        end

        with_replacement_file(file, "[]" => "[\"--threads=5\"]") do newfile
            server = QuartoNotebookRunner.Server()
            json = QuartoNotebookRunner.run!(server, newfile; showprogress = false)
            @test contains(json.cells[2].outputs[1].text, "set_via_env")
            @test json.cells[4].outputs[1].text == "5"
            close!(server)
        end
    end
end
