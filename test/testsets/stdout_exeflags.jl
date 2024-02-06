include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/stdout_exeflags.qmd")) do json
    cells = json["cells"]
    cell = cells[8]
    @test contains(cell["outputs"][1]["text"], "┌ Info: info text")
end

@testset "exeflags notebook restart" begin
    mktempdir() do dir
        content = read(joinpath(@__DIR__, "../examples/stdout_exeflags.qmd"), String)
        cd(dir) do
            server = QuartoNotebookRunner.Server()
            write("notebook.qmd", content)
            json = QuartoNotebookRunner.run!(server, "notebook.qmd"; showprogress = false)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "┌ Info: info text")

            content = replace(content, "--color=no" => "--color=yes")
            write("notebook.qmd", content)
            json = QuartoNotebookRunner.run!(server, "notebook.qmd"; showprogress = false)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "\e[1mInfo: \e[22m\e[39minfo text")

            close!(server)
        end
    end
end
