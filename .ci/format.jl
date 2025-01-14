import JuliaFormatter

cd(dirname(@__DIR__)) do
    formatted_paths = String[]
    unformatted_paths = String[]
    subdirs = ["src", "test", ".ci"]
    for subdir in subdirs
        for (root, dirs, files) in walkdir(subdir)
            for file in files
                fullpath = joinpath(root, file)
                fullpath_lowercase = lowercase(fullpath)
                if endswith(fullpath_lowercase, ".jl") &&
                   !contains(fullpath_lowercase, "vendor")
                    is_formatted = JuliaFormatter.format(fullpath)
                    if is_formatted
                        push!(formatted_paths, fullpath)
                    else
                        push!(unformatted_paths, fullpath)
                    end
                end
            end
        end
    end
    n = length(formatted_paths) + length(unformatted_paths)
    println("Processed $(n) files.")
    println("Formatted correctly: $(length(formatted_paths))")
    println("Not formatted correctly: $(length(unformatted_paths))")
    if !isempty(unformatted_paths)
        println("The following files are not formatted correctly:")
        [println(x) for x in unformatted_paths]
        throw(ErrorException("Some files are not formatted correctly"))
    end
end
