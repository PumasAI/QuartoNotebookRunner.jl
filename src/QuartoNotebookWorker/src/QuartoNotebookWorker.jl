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

const packages = let
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    uuid = Base.UUID(project["uuid"])
    key = "packages"
    is_precompiling() && Base.record_compiletime_preference(uuid, key)
    Base.get_preferences(uuid)[key]
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

# TODO: currently we cannot use package extensions for this code that is loaded
# via `Requires.jl` since we appear to have encountered a potential bug with
# the combination of a system image that contains dependencies that are
# referenced below, versions of Julia from  1.10.5 onwards, and package
# extensions that triggers cyclic dependency check errors even though they
# appear, at least on the surface, to be false positives.
import .Packages.Requires
function __init__()
    Requires.@require CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0" include(
        "../ext/QuartoNotebookWorkerCairoMakieExt.jl",
    )
    Requires.@require DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0" begin
        Requires.@require Tables = "bd369af6-aec1-5ad0-b16a-f7cc5008161c" include(
            "../ext/QuartoNotebookWorkerDataFramesTablesExt.jl",
        )
    end
    Requires.@require JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6" include(
        "../ext/QuartoNotebookWorkerJSONExt.jl",
    )
    Requires.@require LaTeXStrings = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f" include(
        "../ext/QuartoNotebookWorkerLaTeXStringsExt.jl",
    )
    Requires.@require Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a" include(
        "../ext/QuartoNotebookWorkerMakieExt.jl",
    )
    Requires.@require PlotlyBase = "a03496cd-edff-5a9b-9e67-9cda94a718b5" include(
        "../ext/QuartoNotebookWorkerPlotlyBaseExt.jl",
    )
    Requires.@require PlotlyJS = "f0f68f2c-4968-5e81-91da-67840de0976a" include(
        "../ext/QuartoNotebookWorkerPlotlyJSExt.jl",
    )
    Requires.@require Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80" include(
        "../ext/QuartoNotebookWorkerPlotsExt.jl",
    )
    Requires.@require RCall = "6f49c342-dc21-5d91-9882-a32aef131414" include(
        "../ext/QuartoNotebookWorkerRCallExt.jl",
    )
    Requires.@require Revise = "295af30f-e4ad-537b-8983-00126c2a3abe" include(
        "../ext/QuartoNotebookWorkerReviseExt.jl",
    )
    Requires.@require SymPyCore = "458b697b-88f0-4a86-b56b-78b75cfb3531" include(
        "../ext/QuartoNotebookWorkerSymPyCoreExt.jl",
    )
end

# Imports.

import InteractiveUtils
import Logging
import Pkg
import REPL

# Includes.

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

end
