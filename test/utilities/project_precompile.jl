# Update and precompile all project TOMLs when in CI.
if get(ENV, "CI", "false") == "true"
    # To avoid warnings related to GKS during CI runs on Linux with Plots.jl GR backend.
    if Sys.islinux()
        ENV["GKS_ENCODING"] = "utf8"
        ENV["GKSwstype"] = "nul"
    end
    if VERSION >= v"1.10"
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
end
