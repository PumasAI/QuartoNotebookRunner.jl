# CI environment setup.
if get(ENV, "CI", "false") == "true"
    # To avoid warnings related to GKS during CI runs on Linux with Plots.jl GR backend.
    if Sys.islinux()
        ENV["GKS_ENCODING"] = "utf8"
        ENV["GKSwstype"] = "nul"
    end
end
