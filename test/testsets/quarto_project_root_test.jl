@testitem "quarto project root" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        projectA = joinpath(dir, "projectA")
        projectB = joinpath(dir, "projectB")
        mkpath(projectA)
        mkpath(projectB)

        qmd = """
        ---
        engine: julia
        ---

        ```{julia}
        ENV["QUARTO_PROJECT_ROOT"]
        ```
        """

        notebook_a = joinpath(projectA, "a.qmd")
        notebook_b = joinpath(projectB, "b.qmd")
        write(notebook_a, qmd)
        write(notebook_b, qmd)

        server = QNR.Server()
        try
            buf_a = IOBuffer()
            QNR.run!(
                server,
                notebook_a;
                options = Dict{String,Any}("projectDir" => projectA),
                output = buf_a,
                showprogress = false,
            )
            json_a = RTS.JSON3.read(seekstart(buf_a), Any)
            RTS.validate_notebook(json_a)

            buf_b = IOBuffer()
            QNR.run!(
                server,
                notebook_b;
                options = Dict{String,Any}("projectDir" => projectB),
                output = buf_b,
                showprogress = false,
            )
            json_b = RTS.JSON3.read(seekstart(buf_b), Any)
            RTS.validate_notebook(json_b)

            output_a = json_a["cells"][2]["outputs"][1]["data"]["text/plain"]
            output_b = json_b["cells"][2]["outputs"][1]["data"]["text/plain"]

            @test contains(output_a, "projectA")
            @test !contains(output_a, "projectB")

            @test contains(output_b, "projectB")
            @test !contains(output_b, "projectA")
        finally
            QNR.close!(server)
        end
    end
end
