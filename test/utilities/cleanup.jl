let removed = []
    for (root, dirs, files) in walkdir(joinpath(@__DIR__, ".."); topdown = false)
        abspath(root) == abspath(joinpath(@__DIR__, "..", "assets")) && continue

        for file in files
            _, ext = splitext(file)
            if ext in (".html", ".pdf", ".tex", ".docx", ".typ", ".ipynb", ".png", ".css")
                path = joinpath(root, file)
                push!(removed, path)
                rm(path; force = true)
            end
        end
        for dir in dirs
            path = joinpath(root, dir)
            if isempty(readdir(path))
                push!(removed, path)
                rm(path; force = true, recursive = true)
            end
        end
    end
    @info "removed files and directories" removed
end
