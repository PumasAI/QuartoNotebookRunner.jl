module NotebookState

import Pkg

import ..QuartoNotebookWorker

# NotebookContext holds per-notebook state for multi-notebook workers
mutable struct NotebookContext
    file::String                    # Absolute notebook path (context key)
    project::String                 # Julia project path for this notebook
    options::Dict{String,Any}       # Notebook-level options (per-file)
    mod::Module                     # Isolated notebook module
    cwd::String                     # Working directory
    env_vars::Vector{String}        # Environment variables for this notebook
end

# Task-local storage keys
const CONTEXT_KEY = :__quarto_notebook_context__
const CELL_OPTIONS_KEY = :__quarto_cell_options__

is_precompiling() = ccall(:jl_generating_output, Cint, ()) == 1

function with_context(f, ctx::NotebookContext)
    task_local_storage(CONTEXT_KEY, ctx) do
        f()
    end
end

function current_context()
    get(task_local_storage(), CONTEXT_KEY, nothing)
end

function with_cell_options(f, cell_options::AbstractDict)
    task_local_storage(CELL_OPTIONS_KEY, cell_options) do
        f()
    end
end

function current_cell_options()
    get(task_local_storage(), CELL_OPTIONS_KEY, Dict{String,Any}())
end

# Snapshot/restore ENV around render
function with_env_vars(f, vars::Vector{String})
    isempty(vars) && return f()

    # Parse and snapshot
    saved = Dict{String,Union{String,Nothing}}()
    for each in vars
        k, v = Base.splitenv(each)
        saved[k] = get(ENV, k, nothing)
        ENV[k] = v
    end
    try
        return f()
    finally
        for (k, v) in saved
            if v === nothing
                delete!(ENV, k)
            else
                ENV[k] = v
            end
        end
    end
end

function clear_notebook_module!(mod::Module)
    for name in names(mod; all = true)
        if isdefined(mod, name) && !Base.isdeprecated(mod, name)
            try
                Base.setproperty!(mod, name, nothing)
            catch error
                @debug "failed to undefine:" name error
            end
        end
    end
    GC.gc()
end

function define_notebook_module!()
    new_mod = Module(:Notebook)

    # Skip module setup during precompilation - can't eval into dynamic modules
    if is_precompiling()
        return new_mod
    end

    # Add some default imports. Rather than directly using `import` we just
    # `const` them directly from the `Function` objects themselves.
    imports = quote
        # We can import `QuartoNotebookWorker` since we have pushed it onto the
        # end of `LOAD_PATH`.
        import QuartoNotebookWorker.Pkg
        using QuartoNotebookWorker.InteractiveUtils

        const ojs_define = $(QuartoNotebookWorker.ojs_define)
        const include = $(QuartoNotebookWorker.NotebookInclude.include)
        const eval = $(QuartoNotebookWorker.NotebookInclude.eval)
    end
    Core.eval(new_mod, imports)

    return new_mod
end

function notebook_module()
    ctx = current_context()
    ctx === nothing ? nothing : ctx.mod
end

# Test helper: run code with options/cell_options set in task-local storage
function with_test_context(
    f;
    options = Dict{String,Any}(),
    cell_options = Dict{String,Any}(),
)
    mod = define_notebook_module!()
    ctx = NotebookContext(
        "",                       # file
        Base.active_project(),    # project
        options,
        mod,
        pwd(),                    # cwd
        String[],                 # env_vars
    )
    with_context(ctx) do
        with_cell_options(cell_options) do
            f()
        end
    end
end

end
