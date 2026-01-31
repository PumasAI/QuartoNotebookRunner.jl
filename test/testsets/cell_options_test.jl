@testitem "cell options validation" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    # Helper for testing error messages on older Julia versions
    macro test_throws_message(message::String, exp)
        quote
            threw_exception = false
            try
                $(esc(exp))
            catch e
                threw_exception = true
                @test occursin($message, e.msg)
            end
            @test threw_exception
        end
    end

    mktempdir() do dir
        # Valid cell options
        text = """
               ```{julia}
               #| valid: true
               ```
               """
        @test QNR.extract_cell_options(text; file = "file.qmd", line = 1) ==
              Dict("valid" => true)

        text = """
               ```{julia}
               #| multiline:
               #|   - 1
               #|   - 2
               ```
               """
        @test QNR.extract_cell_options(text; file = "file.qmd", line = 1) ==
              Dict("multiline" => [1, 2])

        text = """
               ```{julia}
               #| valid: true
               #| invalid
               ```
               """
        @test_throws_message "file.qmd:1" QNR.extract_cell_options(
            text;
            file = "file.qmd",
            line = 1,
        )

        text = """
               ```{julia}
               #| invalid:true
               ```
               """
        @test_throws_message "file.qmd:1" QNR.extract_cell_options(
            text;
            file = "file.qmd",
            line = 1,
        )

        text = """
               ```{julia}
               a = 1
               ```
               """
        @test QNR.extract_cell_options(text; file = "file.qmd", line = 1) == Dict()

        notebook = joinpath(dir, "notebook.qmd")
        write(
            notebook,
            """
                ---
                title: "Invalid cell option"
                ---

                ```{julia}
                #| this is not yaml
                ```
                """,
        )

        server = QNR.Server()

        buffer = IOBuffer()
        @test_throws_message "Invalid cell attributes type at" QNR.run!(
            server,
            notebook;
            output = buffer,
            showprogress = false,
        )

        QNR.close!(server)
    end
end

@testitem "Invalid eval option" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    macro test_throws_message(message::String, exp)
        quote
            threw_exception = false
            try
                $(esc(exp))
            catch e
                threw_exception = true
                @test occursin($message, e.msg)
            end
            @test threw_exception
        end
    end

    mktempdir() do dir
        notebook = joinpath(dir, "notebook.qmd")
        write(
            notebook,
            """
            ---
            title: "Invalid eval option"
            ---

            ```{julia}
            #| eval: 1
            ```
            """,
        )

        server = QNR.Server()

        buffer = IOBuffer()
        @test_throws_message "Cannot handle an `eval` code cell option with value 1, only true or false." QNR.run!(
            server,
            notebook;
            output = buffer,
            showprogress = false,
        )

        QNR.close!(server)
    end
end

@testitem "cell_options" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server =
        RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "cell_options.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    # Cell-level eval options
    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"
    cell = cells[4]
    @test isempty(cell["outputs"])
    @test cell["execution_count"] == 0
    cell = cells[6]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    # Frontmatter-level eval: false with cell overrides
    cell = cells[8]
    @test isempty(cell["outputs"])
    @test cell["execution_count"] == 0
    cell = cells[10]
    @test !isempty(cell["outputs"])
    @test occursin("should run", cell["outputs"][1]["text"])

    QNR.close!(server)
end
