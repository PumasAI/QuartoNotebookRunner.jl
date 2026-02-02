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

const packages = map(["Requires", "PackageExtensionCompat", "IOCapture"]) do each
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

include("WorkerIPC.jl")
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

# Worker IPC dispatch - routes typed requests from host
dispatch(::WorkerIPC.ManifestInSyncRequest) = _manifest_in_sync()
dispatch(req::WorkerIPC.WorkerInitRequest) = worker_init(req.path, req.options)
dispatch(req::WorkerIPC.WorkerRefreshRequest) = worker_refresh(req.options)
dispatch(req::WorkerIPC.SetEnvVarsRequest) = set_env_vars(req.vars)
dispatch(req::WorkerIPC.RenderRequest) =
    render(req.code, req.file, req.line, req.cell_options; inline = req.inline)
dispatch(req::WorkerIPC.EvaluateParamsRequest) = evaluate_params(req.params)

# Initialize worker for a notebook
function worker_init(path::String, options::Dict)
    NotebookState.PROJECT[] = Base.active_project()
    NotebookState.PATH[] = path
    NotebookState.OPTIONS[] = options
    NotebookState.define_notebook_module!(Main)
    return nothing
end

# Refresh worker state
function worker_refresh(options::Dict)
    refresh!(NotebookState.PATH[], NotebookState.OPTIONS[], options)
    revise_hook()
    return nothing
end

# Set environment variables
function set_env_vars(vars::Vector)
    for each in vars
        k, v = Base.splitenv(each)
        ENV[k] = v
    end
    return nothing
end

# Evaluate parameter assignments as constants in Notebook module
function evaluate_params(params::Dict)
    mod = NotebookState.notebook_module()
    for (key, value) in params
        Core.eval(mod, :(const $(Symbol(key)) = $value))
    end
    return nothing
end

end
