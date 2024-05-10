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
