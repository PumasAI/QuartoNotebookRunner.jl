module QuartoNotebookWorker

# Exports:

export Cell
export expand

export cell_options
export notebook_options


walk(x, _, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))
postwalk(f, x) = walk(x, x -> postwalk(f, x), f)

module Packages

import QuartoNotebookWorker: postwalk

import TOML

is_precompiling() = ccall(:jl_generating_output, Cint, ()) == 1

const packages = map(["BSON", "Requires", "PackageExtensionCompat", "IOCapture"]) do each
    joinpath(@__DIR__, "vendor", each, "src", "$each.jl")
end
const rewrites = Set(Symbol.(first.(splitext.(basename.(packages)))))

function rewrite_import_or_using(expr::Expr)
    return postwalk(expr) do ex
        if Meta.isexpr(ex, :(.))
            root = get(ex.args, 1, nothing)
            root in rewrites && prepend!(ex.args, [fullname(@__MODULE__)..., root])
        end
        ex
    end
end

is_include(ex) =
    Meta.isexpr(ex, :call) &&
    length(ex.args) == 2 &&
    ex.args[1] == :include &&
    isa(ex.args[2], String)

function rewrite_include(ex::Expr)
    # Turns the 1-argument `include` calls into the 2-argument form where the
    # first argument is the `rewriter` function that transforms the parsed
    # expressions before evaluation.
    insert!(ex.args, 2, rewriter)
    return ex
end

function rewriter(expr)
    return postwalk(expr) do ex
        if Meta.isexpr(ex, [:import, :using])
            return rewrite_import_or_using(ex)
        elseif is_include(ex)
            return rewrite_include(ex)
        else
            return ex
        end
    end
end

# Included as a separate file to allow `Revise` to handle updates to this file,
# since we use `include(mapexpr, path)` to transform the included package code.
include("packages.jl")

end

# Handle older versions of Julia that don't have support for package extensions.
# Note that this macro must be called in the root-module of a package, otherwise
# `pathof(__module__)` will be `nothing`.
import .Packages.PackageExtensionCompat: @require_extensions
function __init__()
    @require_extensions
end

# Imports.

import InteractiveUtils
import Logging
import Pkg
import REPL
import Random

# Includes.

include("shared.jl")
include("Malt.jl")
include("package_hooks.jl")
include("InlineDisplay.jl")
include("NotebookState.jl")
include("NotebookInclude.jl")
include("refresh.jl")
include("cell_expansion.jl")
include("render.jl")
include("utilities.jl")
include("ojs_define.jl")
include("notebook_metadata.jl")
include("manifest_validation.jl")
include("python.jl")

if VERSION >= v"1.12-rc1"
    include("PrecompileTools-post1.12/PrecompileTools.jl")
else
    include("PrecompileTools-pre1.12/PrecompileTools.jl")
end
include("precompile.jl")

end
