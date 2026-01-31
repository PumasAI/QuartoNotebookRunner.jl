@testitem "stdout_exeflags" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "stdout_exeflags.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]
    cell = cells[8]
    @test contains(cell["outputs"][1]["text"], "┌ Info: info text")

    QNR.close!(server)
end

@testitem "exeflags notebook restart" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import JSON3

    mktempdir() do dir
        content = read(joinpath(@__DIR__, "..", "examples", "stdout_exeflags.qmd"), String)
        cd(dir) do
            server = QNR.Server()
            write("notebook.qmd", content)
            json = QNR.run!(server, "notebook.qmd"; showprogress = false)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "┌ Info: info text")

            content = replace(content, "--color=no" => "--color=yes")
            write("notebook.qmd", content)
            json = QNR.run!(server, "notebook.qmd"; showprogress = false)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "\e[1mInfo: \e[22m\e[39minfo text")

            QNR.close!(server)
        end
    end
end
