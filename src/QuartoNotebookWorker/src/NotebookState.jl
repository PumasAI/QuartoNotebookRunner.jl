module NotebookState

import Pkg

import ..QuartoNotebookWorker

const PROJECT = Ref("")
const OPTIONS = Ref(Dict{String,Any}())
const CELL_OPTIONS = Ref(Dict{String,Any}())

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
        # We can import `QuartoNotebookWorker` since we have pushed it onto the
        # end of `LOAD_PATH`.
        import QuartoNotebookWorker.Pkg
        using QuartoNotebookWorker.InteractiveUtils

        const ojs_define = $(QuartoNotebookWorker.ojs_define)
        const include = $(QuartoNotebookWorker.NotebookInclude.include)
        const eval = $(QuartoNotebookWorker.NotebookInclude.eval)
    end
    Core.eval(mod, imports)

    return mod
end

const NotebookModuleForPrecompile = Base.RefValue{Union{Nothing,Module}}(nothing)

# `getfield` ends up throwing a segfault here, `getproperty` works fine though.
notebook_module() =
    NotebookModuleForPrecompile[] === nothing ? Base.getproperty(Main, :Notebook)::Module :
    NotebookModuleForPrecompile[]

end
