include("../utilities/prelude.jl")

@testset "Const redefinition" begin
    mktempdir() do dir
        # Ensure that when we update a running notebook and try to re-evaluate
        # cells that contain const definitions that have changed, e.g. structs
        # or consts that we still get the correct output and not redefinition
        # errors.
        notebook = joinpath(dir, "notebook.qmd")
        write(
            notebook,
            """
            ---
            title: "Const redefinition"
            ---

            ```{julia}
            struct T
                x::Int
            end
            ```

            ```{julia}
            const t = T(1)
            ```
            """,
        )

        server = QuartoNotebookRunner.Server()

        buffer = IOBuffer()
        QuartoNotebookRunner.run!(server, notebook; output = buffer, showprogress = false)

        seekstart(buffer)
        json = JSON3.read(buffer, Any)

        @test JSONSchema.validate(SCHEMA, json) === nothing

        cells = json["cells"]

        cell = cells[2]
        @test only(cell["outputs"]) == Dict(
            "output_type" => "execute_result",
            "execution_count" => 1,
            "data" => Dict(),
            "metadata" => Dict(),
        )

        cell = cells[4]
        @test only(cell["outputs"]) == Dict(
            "output_type" => "execute_result",
            "execution_count" => 1,
            "data" => Dict("text/plain" => "T(1)"),
            "metadata" => Dict(),
        )

        write(
            notebook,
            """
            ---
            title: "Const redefinition"
            ---

            ```{julia}
            struct T
                x::String
            end
            ```

            ```{julia}
            const t = T("")
            ```
            """,
        )

        buffer = IOBuffer()
        QuartoNotebookRunner.run!(server, notebook; output = buffer, showprogress = false)

        seekstart(buffer)
        json = JSON3.read(buffer, Any)

        @test JSONSchema.validate(SCHEMA, json) === nothing

        cells = json["cells"]

        cell = cells[2]
        @test only(cell["outputs"]) == Dict(
            "output_type" => "execute_result",
            "execution_count" => 1,
            "data" => Dict(),
            "metadata" => Dict(),
        )

        cell = cells[4]
        @test only(cell["outputs"]) == Dict(
            "output_type" => "execute_result",
            "execution_count" => 1,
            "data" => Dict("text/plain" => "T(\"\")"),
            "metadata" => Dict(),
        )

        close!(server)
    end
end
