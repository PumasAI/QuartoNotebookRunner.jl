"""
This module handles generation of the vendored dependencies for the "real"
`QuartoNotebookWorker` package that lives in the `src/QuartoNotebookWorker`
directory. We want to vendored external dependencies to ensure that the worker
package is self-contained and our dependencies don't conflict with any that a
user might want to import into their notebook.

Most of what this module does is at precompilation time. It gathers the
dependencies of the vendored packages and serializes the source code of the
vendored packages. This serialized source code is then deserialized and loaded
into the `QuartoNotebookWorker` package when it is precompiled. We encode the
roots of each vendored package as a preference in the `QuartoNotebookWorker`
project file. This allows us to trigger recompilation of the worker package when
the vendored packages change since the paths passed as preferences will change.
"""
module QuartoNotebookWorker

# Imports.

import Pkg
import RelocatableFolders
import Serialization
import Scratch
import TOML

# Vendored packages.

import IOCapture
import PackageExtensionCompat

# Dependency detection.

function stdlib_dir()
    normpath(
        joinpath(
            Sys.BINDIR::String,
            "..",
            "share",
            "julia",
            "stdlib",
            "v$(VERSION.major).$(VERSION.minor)",
        ),
    )
end

function gather_packages(modules::Vector{Module})
    pkgids = Base.PkgId.(modules)

    is_stdlib(path) = startswith(path, Sys.STDLIB) && ispath(path)

    packages = []
    stdlibs = []
    function gather!(pkgid::Base.PkgId)
        pkgid in packages && return nothing

        entry_point = Base.locate_package(pkgid)
        if isnothing(entry_point)
            @info "skipping package" pkgid
            return nothing
        end

        if is_stdlib(entry_point)
            push!(stdlibs, pkgid)
            return nothing
        end

        root = dirname(dirname(entry_point))
        for each in ("JuliaProject.toml", "Project.toml")
            project_file = joinpath(root, each)
            if isfile(project_file)
                project_toml = TOML.parsefile(project_file)
                version = project_toml["version"]
                pushfirst!(packages, pkgid => VersionNumber(version))
                deps = project_toml["deps"]
                for (name, uuid) in deps
                    gather!(Base.PkgId(Base.UUID(uuid), name))
                end
                return nothing
            end
        end

        error("Project file not found for: $pkgid.")
    end

    for pkgid in pkgids
        gather!(pkgid)
    end

    return (; packages, stdlibs)
end

# Expression rewriting.

walk(x, _, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))
postwalk(f, x) = walk(x, x -> postwalk(f, x), f)

function rewrite_import_or_using(expr::Expr, rewrites::Dict{Symbol,Vector{Symbol}})
    return postwalk(expr) do ex
        if Meta.isexpr(ex, :(.))
            root = get(ex.args, 1, nothing)
            haskey(rewrites, root) && prepend!(ex.args, rewrites[root])
        end
        ex
    end
end

function extract_module_doc(expr::Expr, name::Symbol)
    if Meta.isexpr(expr, :macrocall, 4) && expr.args[1] == GlobalRef(Core, Symbol("@doc"))
        docs = expr.args[3]
        modexpr = expr.args[4]
        push!(modexpr.args[end].args, :(@doc $docs $name))
        return modexpr
    end
    return expr
end

function parse_source(source::String, entry_point, rewrites)
    expr = Meta.parseall(source)

    Meta.isexpr(expr, :toplevel) || error("Invalid source, not toplevel.")
    isa(expr.args[1], LineNumberNode) || error("Invalid source, not linenumbernode.")

    if !isnothing(entry_point)
        expr = expr.args[end]
        expr = extract_module_doc(expr, Symbol(entry_point))

        Meta.isexpr(expr, :module) || error("Expected module expr $expr")

        expr = expr.args[end]
        Meta.isexpr(expr, :block) || error("Expected block expr $expr")
    end

    expr = postwalk(expr) do ex
        if Meta.isexpr(ex, [:using, :import])
            ex = rewrite_import_or_using(ex, rewrites)
        end
        ex
    end

    return expr
end

# Source serialization and loader generation.

function serialize_source(source, entry_point, rewrites)
    expr = parse_source(source, entry_point, rewrites)
    buffer = IOBuffer()
    Serialization.serialize(buffer, expr)
    return take!(buffer)
end

const LOADER_CODE = RelocatableFolders.@path joinpath(@__DIR__, "loader.jl")

function loader(name::Union{String,Nothing})
    buffer = IOBuffer()
    isnothing(name) || println(buffer, "module $name")
    println(buffer, rstrip(read(LOADER_CODE, String)))
    isnothing(name) || println(buffer, "end")
    return take!(buffer)
end

# Package bundling.

function bundle_package(pkgid::Base.PkgId, version::VersionNumber, rewrites)
    entry_point = Base.locate_package(pkgid)
    root = dirname(dirname(entry_point))
    rel_entry_point = relpath(entry_point, root)
    files = Dict{String,Vector{UInt8}}()
    cd(root) do
        for (root, _, filenames) in walkdir("src")
            for filename in filenames
                if endswith(filename, ".jl")
                    path = normpath(joinpath(root, filename))
                    source = String(read(path, String))
                    is_entry_point = path == rel_entry_point
                    entry_point_name = is_entry_point ? pkgid.name : nothing
                    files[path] = loader(entry_point_name)
                    files["$path.$VERSION.jls"] =
                        serialize_source(source, entry_point_name, rewrites)
                end
            end
        end
    end
    return (; files, version, pkgid)
end

function bundle_packages(; packages, stdlibs)
    # Ensure the worker project has the right stdlibs.
    project_file = joinpath(QNW, "Project.toml")
    project_toml = TOML.parsefile(project_file)
    deps = project_toml["deps"]
    for pkgid in stdlibs
        if !haskey(deps, String(pkgid.name))
            error("missing stdlib: $pkgid")
        end
    end

    # Bundle the packages. Swapping out the imports of vendored packages with
    # package-local imports.
    result = []
    prefix = [:QuartoNotebookWorker, :Packages]
    rewrites = Dict(Symbol(pkg.name) => prefix for (pkg, version) in packages)
    for (package, version) in packages
        push!(result, bundle_package(package, version, rewrites))
    end
    return result
end

# Package init-time.

# To allow it to be added to a system image we make sure it is relocatable.
const QNW = RelocatableFolders.@path joinpath(@__DIR__, "QuartoNotebookWorker")
let
    # Any content from the worker package should trigger recompilation in the
    # runner package, for ease of development.
    for (root, dirs, files) in walkdir(QNW)
        for file in files
            include_dependency(joinpath(root, file))
        end
    end
end

# This contains the serialized code for the vendored packages.
const VENDORED_PACKAGES = bundle_packages(; gather_packages([
    # The list of packages to be vendored.
    IOCapture,
    PackageExtensionCompat,
])...)

# So that we key the loader environment on the vendored package versions.
const LOADER_HASH = string(Base.hash([pkg.version for pkg in VENDORED_PACKAGES]); base = 62)

# Add package init-time we store the path to the scratch spaces used to store
# the deserialized vendored packages. These paths are passed as preferences to
# the loader environment such that the worker package loads the right vendored
# packages and when we load a different version of the vendored packages we
# trigger recompilation of the worker package.
const PACKAGE_DIRS = Dict{Base.PkgId,String}()
const LOADER_ENV = Ref("")

# Since we start a task to perform the loader env setup at package init-time we
# don't want that to block `using QuartoNotebookRunner` so we lock the setup
# task to allow prevention of starting the loader env until
const WORKER_SETUP_LOCK = ReentrantLock()

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        Threads.@spawn begin
            lock(WORKER_SETUP_LOCK) do
                loader_env = "loader.$VERSION.$LOADER_HASH"
                LOADER_ENV[] = Scratch.@get_scratch!(loader_env)

                loader_project_toml = joinpath(LOADER_ENV[], "Project.toml")

                packages = []
                for pkg in VENDORED_PACKAGES
                    package_dir = "vendored.$(VERSION).$(pkg.pkgid.name).$(pkg.version)"
                    root = Scratch.@get_scratch!(package_dir)
                    for (path, content) in pkg.files
                        fullpath = joinpath(root, path)
                        mkpath(dirname(fullpath))
                        write(fullpath, content)
                    end
                    push!(packages, joinpath(root, "src", "$(pkg.pkgid.name).jl"))
                    PACKAGE_DIRS[pkg.pkgid] = root
                end

                toml =
                    isfile(loader_project_toml) ? TOML.parsefile(loader_project_toml) :
                    Dict()
                toml["preferences"] =
                    Dict("QuartoNotebookWorker" => Dict("packages" => packages))
                open(loader_project_toml, "w") do io
                    TOML.print(io, toml)
                end

                mktempdir() do dir
                    file = joinpath(dir, "setup.jl")
                    write(
                        file,
                        """
                        pushfirst!(LOAD_PATH, "@")
                        import Pkg
                        Pkg.develop(; path = $(repr(QNW)))
                        Pkg.update()
                        Pkg.precompile()
                        """,
                    )
                    julia = Base.julia_cmd()[1]
                    project = LOADER_ENV[]
                    cmd = `$(julia) --startup-file=no --project=$project $file`
                    success(cmd) || run(cmd)
                end
            end
        end
    end
end

# Debugging utilities.

"""
    debug()

Run an interactive Julia REPL within the `QuartoNotebookWorker` environment. If
you have `Revise`, `Debugger`, or `TestEnv` available they will be loaded.
Editing code in the `src/QuartoNotebookWorker` directory will be reflected in
the running REPL. Use

```julia
julia> TestEnv.activate("QuartoNotebookWorker"); cd("test")

julia> include("runtests.jl")
```

to run the test suite without having to reload the worker package.
"""
function debug(; exeflags = String[])
    if islocked(WORKER_SETUP_LOCK)
        error("Worker setup is in progress. Please try again later.")
    else
        mktempdir() do temp_dir
            file = joinpath(temp_dir, "setup.jl")
            project = LOADER_ENV[]
            write(
                file,
                """
                # Try load `Revise` first, since we want to be able to track
                # changes in the worker package.
                try
                    import Revise
                catch error
                    @info "Revise not available."
                end

                cd($(repr(QNW)))

                pushfirst!(LOAD_PATH, $(repr(project)))

                # Always do a `precompile` so that it's simpler to kill and
                # restart the worker without it potentially being stale.
                import Pkg
                Pkg.precompile()

                import QuartoNotebookWorker

                # Attempt to import some other useful packages.
                try
                    import Debugger
                catch error
                    @info "Debugger not available."
                end
                try
                    import TestEnv
                catch error
                    @info "TestEnv not available."
                end
                """,
            )
            julia = Base.julia_cmd()[1]
            cmd = `$julia $exeflags --startup-file=no -i $file`
            run(cmd)
        end
    end
end

"""
    test()

Run the test suite for `QuartoNotebookWorker`. This is run in isolation from the
current process. If you want to run the tests interactively use `debug()` and
the `TestEnv` package to do so.
"""
function test(; exeflags = String[])
    mktempdir() do temp_dir
        file = joinpath(temp_dir, "runtests.jl")
        project = LOADER_ENV[]
        write(
            file,
            """
            cd($(repr(QNW)))

            pushfirst!(LOAD_PATH, $(repr(project)))

            import Pkg
            Pkg.test("QuartoNotebookWorker")
            """,
        )
        julia = Base.julia_cmd()[1]
        cmd = `$julia $exeflags --startup-file=no $file`
        run(cmd)
    end
end

end
