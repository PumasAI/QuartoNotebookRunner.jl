include("../utilities/prelude.jl")

@testset "Semicolons" begin
    mktempdir() do dir
        content = """
        ---
        title: "Semicolons"
        ---

        ```{julia}
        variable = 1;
        ```

        ```{julia}
        variable
        ```
        """
        path = joinpath(dir, "notebook.qmd")
        write(path, content)

        server = Server()
        json = run!(server, path; showprogress = false)

        cell = json.cells[2]
        @test isempty(cell.outputs[1].data)

        cell = json.cells[4]
        @test cell.outputs[1].data["text/plain"] == "1"

        close!(server)
    end
end
