"""
    test_pr(cmd::Cmd; url::String, rev::String)

Test a PR by running the given command with the PR's changes. `url` defaults to
the `QuartoNotebookRunner.jl` repo. `rev` is required, and should be the branch
name of the PR. `cmd` should be the `quarto render` command to run.
"""
function test_pr(
    cmd::Cmd;
    url::String = "https://github.com/PumasAI/QuartoNotebookRunner.jl",
    rev::String,
)
    # Require the user to already have a `quarto` install on their path.
    quarto = Sys.which("quarto")
    if isnothing(quarto)
        error("Quarto not found. Please install Quarto.")
    end

    # We require at least v1.5.29 to run this backend.
    version = VersionNumber(readchomp(`quarto --version`))
    if version < v"1.5.29"
        error(
            "Quarto version $version is not supported. Please upgrade to at least v1.5.29.",
        )
    end

    mktempdir() do dir
        file = joinpath(dir, "file.jl")
        write(
            file,
            """
            import Pkg
            Pkg.add(; url = $(repr(url)), rev = $(repr(rev)))
            """,
        )
        run(`$(Base.julia_cmd()) --startup-file=no --project=$dir $file`)
        run(
            addenv(
                `$cmd --no-execute-daemon --execute-debug`,
                "QUARTO_JULIA_PROJECT" => dir,
            ),
        )
    end
end
