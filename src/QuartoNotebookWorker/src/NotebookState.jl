module NotebookState

import Pkg

import ..QuartoNotebookWorker

const PROJECT = Ref("")
const OPTIONS = Ref(Dict{String,Any}())

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        PROJECT[] = Base.active_project()
        define_notebook_module!()
    end
end

function reset_active_project!()
    PROJECT[] == Base.active_project() || Pkg.activate(PROJECT[]; io = devnull)
end

function define_notebook_module!(root = Main)
    # Clear as many variables from the previous `Notebook` module as we can.
    if isdefined(root, :Notebook)
        mod = notebook_module()
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
    mod = Module(:Notebook)
    Core.eval(root, :(Notebook = $mod))

    # Add some default imports. Rather than directly using `import` we just
    # `const` them directly from the `Function` objects themselves.
    imports = quote
        const Pkg = $(Pkg)
        const ojs_define = $(QuartoNotebookWorker.ojs_define)
        const include = $(QuartoNotebookWorker.NotebookInclude.include)
        const eval = $(QuartoNotebookWorker.NotebookInclude.eval)
    end
    Core.eval(mod, imports)

    return mod
end

# `getfield` ends up throwing a segfault here, `getproperty` works fine though.
notebook_module() = Base.getproperty(Main, :Notebook)::Module

end
