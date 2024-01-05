import JSON3
import JSONSchema
import NodeJS_18_jll
import quarto_jll

using QuartoNotebookRunner
using Test

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

function with_extension(path, ext)
    root, _ = splitext(path)
    return "$root.$ext"
end

@testset "QuartoNotebookRunner" begin
    @testset "socket server" begin
        cd(@__DIR__) do
            node = NodeJS_18_jll.node()
            client = joinpath(@__DIR__, "client.js")
            port = 4001
            server = QuartoNotebookRunner.serve(; port)
            sleep(1)
            json(cmd) = JSON3.read(read(cmd, String), Any)

            d1 = json(`$node $client $port run $(joinpath("examples", "cell_types.qmd"))`)
            @test length(d1["notebook"]["cells"]) == 6

            d2 = json(`$node $client $port run $(joinpath("examples", "cell_types.qmd"))`)
            @test d1 == d2

            d3 = json(`$node $client $port close $(joinpath("examples", "cell_types.qmd"))`)
            @test d3["status"] == true

            d4 = json(`$node $client $port run $(joinpath("examples", "cell_types.qmd"))`)
            @test d1 == d4

            d5 = json(`$node $client $port stop`)
            @test d5["message"] == "Server stopped."

            wait(server)
        end
    end

    schema = JSONSchema.Schema(
        open(JSON3.read, joinpath(@__DIR__, "schema/nbformat.v4.schema.json")),
    )
    server = QuartoNotebookRunner.Server()
    examples = joinpath(@__DIR__, "examples")

    function common_tests(json)
        @test json["nbformat"] == 4
        @test json["nbformat_minor"] == 5
        @test json["metadata"]["language_info"]["name"] == "julia"
        @test json["metadata"]["language_info"]["version"] == "$VERSION"
        @test json["metadata"]["language_info"]["codemirror_mode"] == "julia"
        @test json["metadata"]["kernel_info"]["name"] == "julia"
    end
    tests = let
        tests = Dict()
        function file(fn, path)
            tests[joinpath(examples, "$path.qmd")] = fn
            tests[joinpath(examples, "$path.jl")] = fn
        end

        file("cell_types") do json
            @test length(json["cells"]) == 6

            cell = json["cells"][1]
            @test cell["cell_type"] == "markdown"
            @test any(line -> contains(line, "Values:"), cell["source"])
            @test contains(cell["source"][1], "\n")
            @test !contains(cell["source"][end], "\n")

            cell = json["cells"][2]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["execution_count"] == 1
            @test cell["outputs"][1]["data"]["text/plain"] == "1"
            @test length(cell["outputs"][1]["data"]) == 1

            cell = json["cells"][3]
            @test cell["cell_type"] == "markdown"
            @test any(line -> contains(line, "Output streams:"), cell["source"])

            cell = json["cells"][4]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "1")

            cell = json["cells"][5]
            @test cell["cell_type"] == "markdown"
            @test any(line -> contains(line, "Errors:"), cell["source"])

            cell = json["cells"][6]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "error"
            @test cell["outputs"][1]["ename"] == "DivideError"
            @test cell["outputs"][1]["evalue"] == "DivideError()"
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "div")
            @test count("top-level scope", traceback) == 1
            @test count(r"cell_types\.(qmd|jl):", traceback) == 1
        end
        file("empty_notebook") do json
            @test length(json["cells"]) == 1
            @test json["cells"][1]["cell_type"] == "markdown"
            @test json["cells"][1]["source"] == []
        end
        file("only_metadata") do json
            @test length(json["cells"]) == 1
            @test json["cells"][1]["cell_type"] == "markdown"
            @test any(
                line -> contains(line, "Markdown content."),
                json["cells"][1]["source"],
            )
        end
        file("stdout") do json
            @test length(json["cells"]) == 12

            cell = json["cells"][1]
            @test cell["cell_type"] == "markdown"
            @test any(line -> contains(line, "Printing:"), cell["source"])

            cell = json["cells"][2]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "1")
            @test cell["outputs"][2]["output_type"] == "execute_result"
            @test isempty(cell["outputs"][2]["data"])

            cell = json["cells"][3]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][4]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "string")

            cell = json["cells"][5]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][6]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "1")
            @test contains(cell["outputs"][1]["text"], "string")

            cell = json["cells"][7]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][8]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "Info:")
            @test contains(cell["outputs"][1]["text"], "info text")
            @test contains(cell["outputs"][1]["text"], "value = 1")

            cell = json["cells"][9]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][10]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "Warning:")
            @test contains(cell["outputs"][1]["text"], "warn text")
            @test contains(cell["outputs"][1]["text"], "value = 2")

            cell = json["cells"][11]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][12]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "Error:")
            @test contains(cell["outputs"][1]["text"], "error text")
            @test contains(cell["outputs"][1]["text"], "value = 3")
        end
        file("stdout_exeflags") do json
            cells = json["cells"]
            cell = cells[8]
            @test contains(cell["outputs"][1]["text"], "┌ Info: info text")
        end
        file("text_plain_mimetypes") do json
            @test length(json["cells"]) == 8

            cell = json["cells"][1]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][2]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["execution_count"] == 1
            @test cell["outputs"][1]["data"]["text/plain"] == "1"

            cell = json["cells"][3]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][4]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["execution_count"] == 1
            @test cell["outputs"][1]["data"]["text/plain"] == "\"string\""

            cell = json["cells"][5]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][6]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["execution_count"] == 1
            @test contains(cell["outputs"][1]["data"]["text/plain"], "5-element Vector")

            cell = json["cells"][7]
            @test cell["cell_type"] == "markdown"

            cell = json["cells"][8]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["execution_count"] == 1
            @test contains(cell["outputs"][1]["data"]["text/plain"], "Dict{Char")
        end
        file("project") do json
            cell = json["cells"][1]
            @test cell["cell_type"] == "markdown"
            @test any(
                line -> contains(line, "Non-global project environment."),
                cell["source"],
            )

            cell = json["cells"][2]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["data"]["text/plain"] == "false"

            cell = json["cells"][6]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "stream"
            @test contains(cell["outputs"][1]["text"], "Activating")
            @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))

            cell = json["cells"][8]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

            cell = json["cells"][10]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test isempty(cell["outputs"][1]["data"])

            cell = json["cells"][12]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["data"]["text/plain"] == "true"
        end
        file("project_exeflags") do json
            cells = json["cells"]

            cell = cells[1]
            @test cell["cell_type"] == "markdown"
            @test any(
                line -> contains(line, "Non-global project environment."),
                cell["source"],
            )

            cell = cells[2]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["data"]["text/plain"] == "false"

            cell = cells[6]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], joinpath("examples", "project"))
            @test contains(cell["outputs"][1]["text"], "[7876af07] Example")

            cell = cells[8]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test isempty(cell["outputs"][1]["data"])

            cell = cells[10]
            @test cell["cell_type"] == "code"
            @test cell["outputs"][1]["output_type"] == "execute_result"
            @test cell["outputs"][1]["data"]["text/plain"] == "true"
        end
        file("errors") do json
            cells = json["cells"]

            cell = cells[2]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "no method matching +")
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:6", traceback) == 1

            cell = cells[4]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "an error")
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:10", traceback) == 1

            cell = cells[6]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "an argument error")
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:14", traceback) == 1

            cell = cells[8]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "character literal contains multiple characters")
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:18", traceback) == (VERSION >= v"1.10" ? 2 : 1)

            cell = cells[10]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "unexpected")
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:22", traceback) == (VERSION >= v"1.10" ? 2 : 1)

            cell = cells[12]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test count("integer division error", traceback) == 1
            @test count("top-level scope", traceback) == 1
            @test count("errors.qmd:26", traceback) == 1
            @test count("(repeats 4 times)", traceback) == 1
            @test count("errors.qmd:27", traceback) == 1

            cell = cells[14]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test contains(traceback, "no method matching +(::SomeType, ::Int64)")

            cell = cells[18]

            outputs = cell["outputs"]
            @test length(outputs) == 5
            @test outputs[1]["output_type"] == "execute_result"
            @test isempty(outputs[1]["data"])

            output = outputs[2]
            @test output["output_type"] == "error"
            @test output["ename"] == "text/plain showerror"
            @test length(output["traceback"]) == 11
            @test contains(output["traceback"][end], "multimedia.jl")

            output = outputs[3]
            @test output["output_type"] == "error"
            @test output["ename"] == "text/html showerror"
            @test length(output["traceback"]) == 9
            @test contains(output["traceback"][end], "multimedia.jl")

            output = outputs[4]
            @test output["output_type"] == "error"
            @test output["ename"] == "text/latex showerror"
            @test length(output["traceback"]) == 9
            @test contains(output["traceback"][end], "multimedia.jl")

            output = outputs[5]
            @test output["output_type"] == "error"
            @test output["ename"] == "image/svg+xml showerror"
            @test length(output["traceback"]) == 9
            @test contains(output["traceback"][end], "multimedia.jl")
        end
        file("cell_dependencies") do json
            cells = json["cells"]

            cell = cells[2]
            @test cell["outputs"][1]["data"]["text/plain"] == "1"

            cell = cells[4]
            @test cell["outputs"][1]["data"]["text/plain"] == "2"

            cell = cells[6]
            traceback = join(cell["outputs"][1]["traceback"], "\n")
            @test count("not defined", traceback) == 1

            cell = cells[8]
            @test cell["outputs"][1]["data"]["text/plain"] == "Any[]"

            cell = cells[10]
            @test contains(cell["outputs"][1]["data"]["text/plain"], "Vector{Any}")
            @test contains(cell["outputs"][1]["data"]["text/plain"], ":item")

            cell = cells[12]
            @test cell["outputs"][1]["data"]["text/plain"] == "\"item\""
        end
        file("mimetypes") do json
            cells = json["cells"]

            cell = cells[6]
            @test !isempty(cell["outputs"][1]["data"]["image/png"])
            @test !isempty(cell["outputs"][1]["data"]["text/html"])
            metadata = cell["outputs"][1]["metadata"]["image/png"]
            @test metadata["width"] > 0
            @test metadata["height"] > 0

            cell = cells[8]
            @test !isempty(cell["outputs"][1]["data"]["image/svg+xml"])
            @test !isempty(cell["outputs"][1]["data"]["image/png"])

            cell = cells[10]
            @test !isempty(cell["outputs"][1]["data"]["text/plain"])
            @test !isempty(cell["outputs"][1]["data"]["text/html"])

            cell = cells[12]
            @test cell["outputs"][1]["output_type"] == "stream"
            @test !isempty(cell["outputs"][1]["text"])

            cell = cells[14]
            @test !isempty(cell["outputs"][1]["data"]["text/plain"])
            @test !isempty(cell["outputs"][1]["data"]["text/html"])

            cell = cells[16]
            @test !isempty(cell["outputs"][1]["data"]["text/plain"])
            @test !isempty(cell["outputs"][1]["data"]["text/latex"])
        end
        file("revise_integration") do json
            cells = json["cells"]

            cell = cells[10]
            @test cell["outputs"][1]["data"]["text/plain"] == "1"

            cell = cells[14]
            @test cell["outputs"][1]["data"]["text/plain"] == "2"
        end
        file("soft_scope") do json
            cells = json["cells"]
            cell = cells[2]
            @test cell["outputs"][1]["data"]["text/plain"] == "55"
        end
        file(joinpath("integrations", "CairoMakie")) do json
            cells = json["cells"]
            cell = cells[6]
            @test cell["outputs"][1]["metadata"]["image/png"] ==
                  Dict("width" => 768, "height" => 576)
        end
        file(joinpath("integrations", "Plots")) do json
            cells = json["cells"]
            cell = cells[6]
            output = cell["outputs"][1]

            @test !isempty(output["data"]["image/png"])
            @test !isempty(output["data"]["image/svg+xml"])
            @test !isempty(output["data"]["text/html"])

            @test output["metadata"]["image/png"] == Dict("width" => 368, "height" => 276)
        end
        file(joinpath("integrations", "ojs_define")) do json
            cells = json["cells"]

            cell = cells[2]
            @test contains(cell["outputs"][1]["data"]["text/plain"], "ojs_define")

            cell = cells[8]
            @test !isempty(cell["outputs"][1]["data"]["text/plain"])
            @test !isempty(cell["outputs"][1]["data"]["text/html"])
        end
        file("cell_options") do json
            cells = json["cells"]
            cell = cells[2]
            @test cell["outputs"][1]["data"]["text/plain"] == "1"
            cell = cells[4]
            @test isempty(cell["outputs"])
            @test cell["execution_count"] == 0
            cell = cells[6]
            @test cell["outputs"][1]["data"]["text/plain"] == "1"
        end
        file("script") do json
            cells = json["cells"]
            @test length(cells) == 3

            cell = cells[1]
            @test cell["cell_type"] == "markdown"
            @test any(line -> contains(line, "Markdown *content*."), cell["source"])

            cell = cells[2]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 1
            @test cell["outputs"][1]["output_type"] == "stream"
            @test cell["outputs"][1]["name"] == "stdout"
            @test contains(cell["outputs"][1]["text"], "Script files")

            cell = cells[3]
            @test cell["cell_type"] == "code"
            @test cell["execution_count"] == 0
            @test isempty(cell["outputs"])
        end

        tests
    end
    for (root, dirs, files) in walkdir(examples)
        for each in files
            _, ext = splitext(each)
            if ext in (".qmd", ".jl") && !contains(root, "TestPackage")
                each = joinpath(examples, root, each)

                buffer = IOBuffer()
                QuartoNotebookRunner.run!(server, each, output = buffer)
                seekstart(buffer)
                json = JSON3.read(buffer, Any)

                @test JSONSchema.validate(schema, json) === nothing

                # File-specific tests.
                @testset "$(relpath(each, pwd()))" begin
                    common_tests(json)
                    get(() -> _ -> @test(false), tests, each)(json)
                end

                ipynb = joinpath(examples, with_extension(each, "ipynb"))
                QuartoNotebookRunner.run!(server, each; output = ipynb)

                # No macOS ARM build, so just look for a local version that the dev
                # should have installed. This avoids having to use rosetta2 to run
                # the x86_64 version of Julia to get access to the x86_64 version of
                # Quarto artifact.
                quarto_bin =
                    quarto_jll.is_available() ? quarto_jll.quarto() : setenv(`quarto`)
                # Just a smoke test to make sure it runs. Use docx since it doesn't
                # output a bunch of folders (html), or require a tinytex install
                # (pdf). All we are doing here at the moment is ensuring quarto doesn't
                # break on our notebook outputs.
                if success(`$quarto_bin --version`)
                    @test success(`$quarto_bin render $ipynb --to docx`)
                else
                    @error "quarto not found, skipping smoke test."
                end

                QuartoNotebookRunner.close!(server, each)
            end
        end
    end

    # Switching exeflags within a running notebook causes it to restart so that
    # the new exeflags can be applied.
    @testset "exeflags notebook restart" begin
        content = read(joinpath(@__DIR__, "examples/stdout_exeflags.qmd"), String)
        mktempdir() do dir
            cd(dir) do
                server = QuartoNotebookRunner.Server()
                write("notebook.qmd", content)
                json = QuartoNotebookRunner.run!(server, "notebook.qmd")

                cells = json.cells
                cell = cells[8]
                @test contains(cell.outputs[1].text, "┌ Info: info text")

                content = replace(content, "--color=no" => "--color=yes")
                write("notebook.qmd", content)
                json = QuartoNotebookRunner.run!(server, "notebook.qmd")

                cells = json.cells
                cell = cells[8]
                @test contains(cell.outputs[1].text, "\e[1mInfo: \e[22m\e[39minfo text")

                close!(server)
            end
        end
    end

    @testset "Const redefinition" begin
        # Ensure that when we update a running notebook and try to re-evaluate
        # cells that contain const definitions that have changed, e.g. structs
        # or consts that we still get the correct output and not redefinition
        # errors.
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

            server = QuartoNotebookRunner.Server()

            buffer = IOBuffer()
            QuartoNotebookRunner.run!(server, notebook; output = buffer)

            seekstart(buffer)
            json = JSON3.read(buffer, Any)

            @test JSONSchema.validate(schema, json) === nothing

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
            QuartoNotebookRunner.run!(server, notebook; output = buffer)

            seekstart(buffer)
            json = JSON3.read(buffer, Any)

            @test JSONSchema.validate(schema, json) === nothing

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
        end
    end

    @testset "render" begin
        buffer = IOBuffer()
        QuartoNotebookRunner.render(
            joinpath(@__DIR__, "examples/cell_types.qmd");
            output = buffer,
        )
        seekstart(buffer)
        json = JSON3.read(buffer, Any)

        @test JSONSchema.validate(schema, json) === nothing
    end

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

        mktempdir() do dir
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
            )
        end
    end

    @testset "Invalid eval option" begin
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

            server = QuartoNotebookRunner.Server()

            buffer = IOBuffer()
            @test_throws_message "Cannot handle an `eval` code cell option with value 1, only true or false." QuartoNotebookRunner.run!(
                server,
                notebook;
                output = buffer,
            )
        end
    end
end
