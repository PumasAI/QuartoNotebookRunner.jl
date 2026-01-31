@testitem "out of sync manifest" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    s = QNR.Server()
    path = joinpath(
        @__DIR__,
        "..",
        "examples",
        "out_of_sync_manifest",
        "out_of_sync_manifest.qmd",
    )
    project = abspath(joinpath(@__DIR__, "..", "examples", "out_of_sync_manifest"))
    if VERSION < v"1.8"
        # Skip on earlier versions. Since the `Pkg` feature does not exist.
    else
        # This creates an environment that does match the required julia
        # version, but with a project file that has been edited to remove the
        # dependency, which triggers the out of sync error.
        julia = Base.julia_cmd()[1]
        code = "pushfirst!(LOAD_PATH, \"@stdlib\"); import Pkg; Pkg.add(\"REPL\"; io = devnull)"
        run(`$julia --project=$project -e $code`)
        open(
            joinpath(@__DIR__, "..", "examples", "out_of_sync_manifest", "Project.toml"),
            "w",
        ) do io
            println(io, "[deps]")
            flush(io)
        end
        @test_throws "Pkg.resolve()" QNR.run!(s, path)
    end
end
