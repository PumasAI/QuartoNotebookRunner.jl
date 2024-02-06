include("../utilities/prelude.jl")

@testset "relative paths in `output`" begin
    mktempdir() do dir
        content = read(joinpath(@__DIR__, "../examples/stdout.qmd"), String)
        cd(dir) do
            server = QuartoNotebookRunner.Server()
            write("notebook.qmd", content)
            ipynb = "notebook.ipynb"
            QuartoNotebookRunner.run!(
                server,
                "notebook.qmd";
                output = ipynb,
                showprogress = false,
            )

            json = JSON3.read(ipynb)

            cells = json.cells
            cell = cells[8]
            @test contains(cell.outputs[1].text, "info text")

            close!(server)
        end
    end
end
