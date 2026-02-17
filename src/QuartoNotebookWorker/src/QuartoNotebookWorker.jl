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

import Dates
import InteractiveUtils
import Logging
import Pkg
import REPL
import Random

# Includes.

include("PrecompileToolsLite.jl")
using .PrecompileToolsLite

include("NotebookState.jl")
include("WorkerIPC.jl")
include("package_hooks.jl")
include("InlineDisplay.jl")
include("NotebookInclude.jl")
include("refresh.jl")
include("cell_expansion.jl")
include("render_io.jl")
include("render_error.jl")
include("render_code.jl")
include("render_mimetypes.jl")
include("render.jl")
include("utilities.jl")
include("ojs_define.jl")
include("notebook_metadata.jl")
include("manifest_validation.jl")
include("python.jl")
include("r.jl")
include("diagnostic_logger.jl")

# Type aliases for dispatch signatures
const Contexts = Dict{String,NotebookState.NotebookContext}

# Worker IPC dispatch - routes typed requests from host

function dispatch(::WorkerIPC.ManifestInSyncRequest, ::Contexts, ::ReentrantLock)
    _manifest_in_sync()
end

function dispatch(
    req::WorkerIPC.NotebookInitRequest,
    contexts::Contexts,
    lock::ReentrantLock,
)
    Logging.@debug "NotebookInit" file = req.file project = req.project
    ctx, options_changed = Base.lock(lock) do
        ctx = get(contexts, req.file, nothing)
        if ctx === nothing
            # Create new context
            mod = NotebookState.define_notebook_module!()
            ctx = NotebookState.NotebookContext(
                req.file,
                req.project,
                req.options,
                mod,
                req.cwd,
                copy(req.env_vars),
                copy(Random.default_rng()),
            )
            contexts[req.file] = ctx
            (ctx, false)
        else
            # Update existing context
            changed = ctx.options != req.options
            ctx.project = req.project
            ctx.options = req.options
            ctx.cwd = req.cwd
            ctx.env_vars = copy(req.env_vars)
            # Clear and recreate notebook module for fresh state
            NotebookState.clear_notebook_module!(ctx.mod)
            ctx.mod = NotebookState.define_notebook_module!()
            ctx.rng_state = copy(Random.default_rng())
            (ctx, changed)
        end
    end
    # Hooks read from current_context() so must run inside with_context.
    # _run_hooks catches all errors, so hooks can't leave the context in a partial state.
    NotebookState.with_context(ctx) do
        options_changed && run_package_loading_hooks()
        run_package_refresh_hooks()
    end
    revise_hook()
    return nothing
end

function dispatch(
    req::WorkerIPC.NotebookCloseRequest,
    contexts::Contexts,
    lock::ReentrantLock,
)
    Logging.@debug "NotebookClose" file = req.file
    Base.lock(lock) do
        ctx = get(contexts, req.file, nothing)
        if ctx !== nothing
            NotebookState.clear_notebook_module!(ctx.mod)
            delete!(contexts, req.file)
        end
    end
    return nothing
end

function dispatch(req::WorkerIPC.RenderRequest, contexts::Contexts, lock::ReentrantLock)
    Logging.@debug "Render" notebook = req.notebook line = req.line
    ctx = Base.lock(lock) do
        get(contexts, req.notebook, nothing)
    end
    ctx === nothing && error("No context for notebook: $(req.notebook)")

    # cd, Pkg.activate, ENV, display stack, log level are process-global.
    # Safe because the host serializes dispatch calls per worker.
    Base.active_project() == ctx.project || Pkg.activate(ctx.project; io = devnull)
    pwd() == ctx.cwd || cd(ctx.cwd)

    # Set SOURCE_PATH for include resolution
    task_local_storage()[:SOURCE_PATH] = ctx.file

    result = NotebookState.with_rng(ctx) do
        NotebookState.with_env_vars(ctx.env_vars) do
            NotebookState.with_context(ctx) do
                NotebookState.with_cell_options(req.cell_options) do
                    render(
                        req.code,
                        req.file,
                        req.line,
                        req.cell_options;
                        inline = req.inline,
                        mod = ctx.mod,
                    )
                end
            end
        end
    end

    # Track if user changed project/cwd during render
    ctx.project = Base.active_project()
    ctx.cwd = pwd()

    return result
end

function dispatch(
    req::WorkerIPC.EvaluateParamsRequest,
    contexts::Contexts,
    lock::ReentrantLock,
)
    ctx = Base.lock(lock) do
        get(contexts, req.file, nothing)
    end
    ctx === nothing && error("No context for notebook: $(req.file)")

    for (key, value) in req.params
        Core.eval(ctx.mod, :(const $(Symbol(key)) = $value))
    end
    return nothing
end

# Precompile hints for methods not reachable via the workload below.
precompile(WorkerIPC.main, ())
precompile(include_str, (Module, String))

@setup_workload begin
    @compile_workload begin
        NotebookState.with_test_context() do
            mod = NotebookState.notebook_module()
            for code in ["1 + 2", "1 + :foo", "println(\"x\")", "@info \"x\"", "[1, 2, 3]"]
                result = render(code, "none", 0; mod)
                # Exercise the serialization round-trip.
                bytes = WorkerIPC._ipc_serialize(result)
                WorkerIPC._ipc_deserialize(bytes)
            end
        end
    end
end

end
