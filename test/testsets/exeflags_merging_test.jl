@testitem "exeflags merging" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

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

    file = joinpath(@__DIR__, "..", "examples", "exeflags_merging.qmd")

    withenv(
        "QUARTONOTEBOOKRUNNER_EXEFLAGS" => "[\"--project=/set_via_env\", \"--threads=3\"]",
    ) do
        server = QNR.Server()
        json = QNR.run!(server, file; showprogress = false)
        @test contains(json.cells[2].outputs[1].text, "set_via_env")
        @test json.cells[4].outputs[1].text == "3"
        QNR.close!(server)

        with_replacement_file(
            file,
            "[]" => "[\"--project=/override_via_frontmatter\"]",
        ) do newfile
            server = QNR.Server()
            json = QNR.run!(server, newfile; showprogress = false)
            @test contains(json.cells[2].outputs[1].text, "override_via_frontmatter")
            @test json.cells[4].outputs[1].text == "3"
            QNR.close!(server)
        end

        with_replacement_file(file, "[]" => "[\"--threads=5\"]") do newfile
            server = QNR.Server()
            json = QNR.run!(server, newfile; showprogress = false)
            @test contains(json.cells[2].outputs[1].text, "set_via_env")
            @test json.cells[4].outputs[1].text == "5"
            QNR.close!(server)
        end
    end
end
