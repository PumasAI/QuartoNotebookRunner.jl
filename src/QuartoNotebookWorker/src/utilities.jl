let cache = Dict{Base.PkgId,VersionNumber}()
    global function _pkg_version(pkgid::Base.PkgId)
        # Cache the package versions since once a version of a package is
        # loaded we don't really support loading a different version of it,
        # so we can just cache the version number.
        if haskey(cache, pkgid)
            return cache[pkgid]
        else
            deps = Pkg.dependencies()
            if haskey(deps, pkgid.uuid)
                return cache[pkgid] = deps[pkgid.uuid].version
            else
                return nothing
            end
        end
    end
end

function _getproperty(f::Base.Callable, obj, property::Symbol)
    if Base.@invokelatest hasproperty(obj, property)
        Base.@invokelatest getproperty(obj, property)
    else
        f()
    end
end
function _getproperty(obj, property::Symbol, fallback)
    if Base.@invokelatest hasproperty(obj, property)
        Base.@invokelatest getproperty(obj, property)
    else
        fallback
    end
end

if VERSION >= v"1.9"
    _flatmap(f, iters...) = Base.Iterators.flatmap(f, iters...)
else
    _flatmap(f, iters...) = Base.Iterators.flatten(Base.Iterators.map(f, iters...))
end

if VERSION >= v"1.8"
    function _parseall(text::AbstractString; filename = "none", lineno = 1)
        Meta.parseall(text; filename, lineno)
    end
else
    function _parseall(text::AbstractString; filename = "none", lineno = 1)
        ex = Meta.parseall(text, filename = filename)
        _walk(x -> _fixline(x, lineno), ex)
        return ex
    end
    function _walk(f, ex::Expr)
        for (nth, x) in enumerate(ex.args)
            ex.args[nth] = _walk(f, x)
        end
        return ex
    end
    _walk(f, @nospecialize(other)) = f(other)

    _fixline(x, line) = x isa LineNumberNode ? LineNumberNode(x.line + line - 1, x.file) : x
end

"""
    remote_repl([port]) -> port_number

Starts up a remote REPL server using `RemoteREPL.jl` in the notebook process.
It requires manually importing `RemoteREPL` into your notebook.

This can be useful for debugging `QuartoNotebookWorker` code directly in the
notebook process that is running the `.qmd` file.

Add the following to a cell in a notebook. Ensure that your notebook has
`RemoteREPL` in it's package dependencies.

```julia
import RemoteREPL
Main.QuartoNotebookWorker.remote_repl()
```

Run `quarto render` to start up the remote REPL. Subsequent renders will reuse
the same server rather than starting up a new one. Check the notebook output
for that cell which should list the port number that the server is running on.

In a separate REPL import `RemoteREPL` and connect using `connect_repl`. Either
provide the port number. If no port was provided in the `remote_repl` call then
the default will be used.
"""
remote_repl(port::Union{Int,Nothing} = nothing) = _remote_repl(nothing, port)
_remote_repl(::Any, port) = error("`RemoteREPL.jl` has not been loaded.")
