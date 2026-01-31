@testitem "relative paths in output" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import JSON3

    mktempdir() do dir
        content = read(joinpath(@__DIR__, "..", "examples", "stdout.qmd"), String)
        cd(dir) do
            server = QNR.Server()
            write("notebook.qmd", content)
            ipynb = "notebook.ipynb"
            QNR.run!(server, "notebook.qmd"; output = ipynb, showprogress = false)

            json = JSON3.read(ipynb)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "info text")

            QNR.close!(server)
        end
    end
end
