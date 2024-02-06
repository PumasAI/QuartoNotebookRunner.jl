# Update and precompile all project TOMLs when in CI.
if get(ENV, "CI", "false") == "true"
    for dir in ["integrations", "mimetypes"]
        for (root, dirs, files) in walkdir(joinpath(@__DIR__, "..", "examples", dir))
            for each in files
                if each == "Project.toml"
                    manifest = joinpath(root, "Manifest.toml")
                    if isfile(manifest)
                        rm(manifest; force = true)
                    end
                    run(
                        `$(Base.julia_cmd()) --project=$root -e 'push!(LOAD_PATH, "@stdlib"); import Pkg; Pkg.update()'`,
                    )
                end
            end
        end
    end
end
