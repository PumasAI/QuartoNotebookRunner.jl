include("../utilities/prelude.jl")

# Julia 1.6 doesn't support testing error messages, yet
macro test_throws_message(message::String, exp)
    quote
        threw_exception = false
        try
            $(esc(exp))
        catch e
            threw_exception = true
            @test occursin($message, e.msg) # Currently only works for ErrorException
        end
        @test threw_exception
    end
end

@testset "cell options" begin
    mktempdir() do dir
        @testset "Invalid cell option" begin
            text = """
                   ```{julia}
                   #| valid: true
                   ```
                   """
            @test QuartoNotebookRunner.extract_cell_options(
                text;
                file = "file.qmd",
                line = 1,
            ) == Dict("valid" => true)

            text = """
                   ```{julia}
                   #| valid: true
                   #| invalid
                   ```
                   """
            @test_throws_message "file.qmd:1" QuartoNotebookRunner.extract_cell_options(
                text;
                file = "file.qmd",
                line = 1,
            )

            text = """
                   ```{julia}
                   a = 1
                   ```
                   """
            @test QuartoNotebookRunner.extract_cell_options(
                text;
                file = "file.qmd",
                line = 1,
            ) == Dict()

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

            server = QuartoNotebookRunner.Server()

            buffer = IOBuffer()
            @test_throws_message "Error parsing cell attributes" QuartoNotebookRunner.run!(
                server,
                notebook;
                output = buffer,
                showprogress = false,
            )

            close!(server)
        end
        @testset "Invalid eval option" begin
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

            server = QuartoNotebookRunner.Server()

            buffer = IOBuffer()
            @test_throws_message "Cannot handle an `eval` code cell option with value 1, only true or false." QuartoNotebookRunner.run!(
                server,
                notebook;
                output = buffer,
                showprogress = false,
            )

            close!(server)
        end
    end
end

test_example(joinpath(@__DIR__, "../examples/cell_options.qmd")) do json
    cells = json["cells"]
    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"
    cell = cells[4]
    @test isempty(cell["outputs"])
    @test cell["execution_count"] == 0
    cell = cells[6]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"
end
