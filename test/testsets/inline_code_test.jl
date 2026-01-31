@testitem "Inline code" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "inline_code.qmd")
        write(
            qmd,
            """
            ---
            title: "Inline code"
            ---

            ```{julia}
            a = 1
            ```

            Some variables `{julia} a + 1`.

            ```{julia}
            struct Custom
                value
            end
            Base.show(io::IO, ::MIME"text/markdown", c::Custom) = print(io, "*\$(c.value)*")
            ```

            Some custom markdown MIME type output `{julia} Custom("markdown")`.

            ```{julia}
            b = Text("*placeholder*")
            ```

            Some `Text` objects *`{julia} b`*. Escaped markdown syntax.

            ```{julia}
            c = "*placeholder*"
            ```

            Some plain `String`s `{julia} c`. Escaped markdown syntax.

            > # A more complex expression `{julia} round(Int, 1.5)`.
            """,
        )

        server = QNR.Server()
        json = QNR.run!(server, qmd; showprogress = false)

        cells = json.cells

        cell = cells[3]
        @test any(contains("Some variables 2."), cell.source)

        cell = cells[5]
        @test any(
            contains("Some custom markdown MIME type output *markdown*."),
            cell.source,
        )

        cell = cells[7]
        @test any(contains("Some `Text` objects *\\*placeholder\\**."), cell.source)

        cell = cells[9]
        @test any(contains("Some plain `String`s \\*placeholder\\*."), cell.source)
        @test any(contains("A more complex expression 2."), cell.source)
    end
end
