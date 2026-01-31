@testitem "Const redefinition" tags = [:notebook] setup = [RunnerTestSetup] begin
    import QuartoNotebookRunner as QNR
    import JSON3
    import JSONSchema
    import .RunnerTestSetup as RTS

    mktempdir() do dir
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

        server = QNR.Server()

        buffer = IOBuffer()
        QNR.run!(server, notebook; output = buffer, showprogress = false)

        seekstart(buffer)
        json = JSON3.read(buffer, Any)

        @test JSONSchema.validate(RTS.SCHEMA, json) === nothing

        cells = json["cells"]

        cell = cells[2]
        @test isempty(cell["outputs"])

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
        QNR.run!(server, notebook; output = buffer, showprogress = false)

        seekstart(buffer)
        json = JSON3.read(buffer, Any)

        @test JSONSchema.validate(RTS.SCHEMA, json) === nothing

        cells = json["cells"]

        cell = cells[2]
        @test isempty(cell["outputs"])

        cell = cells[4]
        @test only(cell["outputs"]) == Dict(
            "output_type" => "execute_result",
            "execution_count" => 1,
            "data" => Dict("text/plain" => "T(\"\")"),
            "metadata" => Dict(),
        )

        QNR.close!(server)
    end
end
