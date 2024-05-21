# Helper script to generate the required folders for extensions. Saves a bit of
# typing.

pushfirst!(LOAD_PATH, "@stdlib")
import TOML
popfirst!(LOAD_PATH)

toml = TOML.parsefile(joinpath(@__DIR__, "Project.toml"))
weakdeps = get!(Dict{String,Any}, toml, "weakdeps")
extensions = get!(Dict{String,Any}, toml, "extensions")

ext_root = joinpath(@__DIR__, "ext")

for (k, v) in weakdeps
    ext_name = "QuartoNotebookWorker$(k)Ext"
    if haskey(extensions, ext_name)
    else
        extensions[ext_name] = k
    end
end

for (ext, deps) in extensions
    for dep in Base.vect(deps)
        if !haskey(weakdeps, dep)
            @error "missing from weakdeps" dep
        end
    end

    ext_file = joinpath(ext_root, "$ext.jl")
    if isfile(ext_file)
    else
        ext_dir = joinpath(ext_root, ext)
        if isdir(ext_dir)
        else
            mkpath(dirname(ext_file))
            open(ext_file, "w") do io
                print(
                    io,
                    """
                    module $ext

                    import QuartoNotebookWorker
                    """,
                )
                for dep in Base.vect(deps)
                    println(io, "import $dep\n")
                end
                println(io, "end")
            end
        end
    end
end

open(joinpath(@__DIR__, "Project.toml"), "w") do io
    TOML.print(io, toml; sorted = true)
end
