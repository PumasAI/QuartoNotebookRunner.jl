@testitem "precompilation_output" tags = [:notebook, :julia110] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    # The notebook needs a project that triggers a worker extension, which the
    # test project itself does not provide.
    mktempdir() do dir
        write(
            joinpath(dir, "Project.toml"),
            """
            [deps]
            JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            """,
        )
        run(
            `$(Base.julia_cmd()) --startup-file=no --project=$dir -e "import Pkg; Pkg.instantiate()"`,
        )

        notebook = joinpath(dir, "precompilation_output.qmd")
        cp(joinpath(@__DIR__, "..", "examples", "precompilation_output.qmd"), notebook)

        # Drop the extension's cache so that the render has to build it, which
        # is what puts the report in front of the filter.
        rm(
            joinpath(
                DEPOT_PATH[1],
                "compiled",
                "v$(VERSION.major).$(VERSION.minor)",
                "QuartoNotebookWorkerJSONExt",
            );
            force = true,
            recursive = true,
        )

        json, server = RTS.run_notebook(notebook)
        RTS.validate_notebook(json)

        cell = json["cells"][2]
        @test cell["cell_type"] == "code"
        @test !any(
            output -> contains(get(output, "text", ""), "Precompiling"),
            cell["outputs"],
        )
        @test cell["outputs"][1]["data"]["text/plain"] == "\"[1,2,3]\""

        QNR.close!(server)
    end
end
