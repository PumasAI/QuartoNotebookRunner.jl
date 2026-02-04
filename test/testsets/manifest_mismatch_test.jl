@testitem "manifest mismatch strict" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    # The commited manifest is for 1.8, so this test would fail on that
    # version. But none of our CI runs on that version so this is a safe
    # version to skip in this test.
    if VERSION < v"1.8" || VERSION > v"1.8"
        s = QNR.Server()
        path = joinpath(
            @__DIR__,
            "..",
            "examples",
            "manifest_mismatch",
            "manifest_mismatch.qmd",
        )
        if VERSION < v"1.8"
            @test_throws QNR.UserError QNR.run!(s, path)
        else
            @test_throws "expected_julia_version = \"1.8.5\"" QNR.run!(s, path)
        end
    end
end

@testitem "manifest lenient" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import Pkg

    mktempdir() do dir
        # Create minimal project
        project_path = joinpath(dir, "Project.toml")
        write(project_path, "[deps]")

        # Compute project_hash the same way Pkg does (varies by Julia version)
        project_hash = if isdefined(Pkg.Types, :workspace_resolve_hash)
            # Julia 1.12+
            env = Pkg.Types.EnvCache(project_path)
            Pkg.Types.workspace_resolve_hash(env)
        elseif isdefined(Pkg.Types, :project_resolve_hash)
            # Julia 1.8-1.11
            project = Pkg.Types.read_project(project_path)
            Pkg.Types.project_resolve_hash(project)
        else
            # Julia 1.6/1.7 - is_manifest_current check skipped, any hash works
            "da39a3ee5e6b4b0d3255bfef95601890afd80709"
        end

        # Create manifest with different patch version
        patch = VERSION.patch == 0 ? 1 : VERSION.patch - 1
        diff_version = "$(VERSION.major).$(VERSION.minor).$patch"

        write(
            joinpath(dir, "Manifest.toml"),
            """
            julia_version = "$diff_version"
            manifest_format = "2.0"
            project_hash = "$project_hash"

            [deps]
            """,
        )

        write(
            joinpath(dir, "notebook.qmd"),
            """
            ---
            title: Lenient test
            engine: julia
            ---
            ```{julia}
            VERSION
            ```
            """,
        )

        s = QNR.Server()
        # Should NOT throw - lenient mode allows patch mismatch
        @test QNR.run!(s, joinpath(dir, "notebook.qmd")) !== nothing
        QNR.close!(s)
    end
end
