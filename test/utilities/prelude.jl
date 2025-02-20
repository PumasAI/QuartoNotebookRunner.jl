using Test
using Logging
using QuartoNotebookRunner

import JSON3
import JSONSchema
import NodeJS_18_jll
import quarto_jll

if !@isdefined(SCHEMA)
    SCHEMA = JSONSchema.Schema(
        open(JSON3.read, joinpath(@__DIR__, "../schema/nbformat.v4.schema.json")),
    )

    function test_example(f, each, options = Dict{String,Any}())
        examples = joinpath(@__DIR__, "../examples")
        name = relpath(each, pwd())
        if isempty(options)
            @info "Testing $name"
        else
            @info "Testing $name (extra options)" options
        end
        @testset "$(name)" begin
            server = QuartoNotebookRunner.Server()
            buffer = IOBuffer()
            QuartoNotebookRunner.run!(
                server,
                each;
                options = options,
                output = buffer,
                showprogress = false,
            )
            seekstart(buffer)
            json = JSON3.read(buffer, Any)

            @test JSONSchema.validate(SCHEMA, json) === nothing

            ## Common tests.
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

            ## File-specific tests.
            f(json)

            function with_extension(path, ext)
                root, _ = splitext(path)
                return "$root.$ext"
            end
            ipynb = joinpath(examples, with_extension(each, "ipynb"))
            QuartoNotebookRunner.run!(server, each; output = ipynb, showprogress = false)

            if !Sys.iswindows()
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
                    @test success(`$quarto_bin render $ipynb --no-execute --to docx`)
                else
                    @error "quarto not found, skipping smoke test."
                end
            end
            QuartoNotebookRunner.close!(server, each)
        end
        GC.gc()
    end
    to_format(format) = Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => format)))
end
