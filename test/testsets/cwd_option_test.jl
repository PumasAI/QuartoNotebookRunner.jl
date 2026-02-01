@testitem "cwd option" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    mktempdir() do project_root
        # Create subdirectory with notebook
        subdir = joinpath(project_root, "docs")
        mkpath(subdir)
        notebook = joinpath(subdir, "test.qmd")
        write(
            notebook,
            """
---
engine: julia
---

```{julia}
pwd()
```
""",
        )

        # Test with cwd = project_root (simulates execute-dir: project)
        options = Dict{String,Any}("cwd" => project_root)
        json, server = RTS.run_notebook(notebook; options)
        RTS.validate_notebook(json)

        # Verify pwd() returned project_root, not subdir
        cell = json["cells"][2]
        output = cell["outputs"][1]["data"]["text/plain"]
        # Check we're not in the docs subdirectory (the key assertion)
        @test !contains(output, "docs")
        # Check we got the temp dir basename (handles Windows path escaping)
        @test contains(output, basename(project_root))

        QNR.close!(server)
    end
end
