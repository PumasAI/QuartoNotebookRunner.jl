@testmodule RunnerTestSetup begin
    using Test
    import QuartoNotebookRunner as QNR
    import JSON3
    import JSONSchema
    import quarto_jll

    const SCHEMA = JSONSchema.Schema(
        open(JSON3.read, joinpath(@__DIR__, "..", "schema", "nbformat.v4.schema.json")),
    )

    """
        run_notebook(path; options=Dict{String,Any}()) -> (json, server)

    Run a notebook and return parsed JSON output and server handle.
    Caller should `QNR.close!(server, path)` after tests.
    """
    function run_notebook(path; options = Dict{String,Any}())
        @info "Running notebook" path
        server = QNR.Server()
        buffer = IOBuffer()
        QNR.run!(server, path; options = options, output = buffer, showprogress = false)
        seekstart(buffer)
        json = JSON3.read(buffer, Any)
        return json, server
    end

    """
        validate_notebook(json)

    Run common notebook validations: schema, nbformat, metadata.
    """
    function validate_notebook(json)
        @test JSONSchema.validate(SCHEMA, json) === nothing

        @test json["nbformat"] == 4
        @test json["nbformat_minor"] == 5
        @test json["metadata"]["language_info"]["name"] == "julia"
        @test isa(
            VersionNumber(json["metadata"]["language_info"]["version"]),
            VersionNumber,
        )
        @test json["metadata"]["language_info"]["codemirror_mode"] == "julia"
        @test json["metadata"]["kernel_info"]["name"] == "julia"
        @test startswith(json["metadata"]["kernelspec"]["name"], "julia")
        @test startswith(json["metadata"]["kernelspec"]["display_name"], "Julia")
        @test json["metadata"]["kernelspec"]["language"] == "julia"
    end

    """
        with_quarto_render(f, path, json, server)

    Render notebook with quarto as smoke test, then run f().
    """
    function with_quarto_render(f, path, json, server)
        function with_extension(p, ext)
            root, _ = splitext(p)
            return "$root.$ext"
        end
        ipynb = with_extension(path, "ipynb")
        docx = with_extension(path, "docx")

        try
            QNR.run!(server, path; output = ipynb, showprogress = false)

            if !Sys.iswindows()
                quarto_bin =
                    quarto_jll.is_available() ? quarto_jll.quarto() : setenv(`quarto`)
                if success(`$quarto_bin --version`)
                    @test success(`$quarto_bin render $ipynb --no-execute --to docx`)
                else
                    @error "quarto not found, skipping smoke test."
                end
            end

            f()
        finally
            isfile(ipynb) && rm(ipynb)
            isfile(docx) && rm(docx)
        end
    end

    to_format(format) = Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => format)))
end
