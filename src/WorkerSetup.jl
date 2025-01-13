"""
This module handles generation of the vendored dependencies for the
`QuartoNotebookWorker` package that lives in the `src/QuartoNotebookWorker`
directory. We want to vendored external dependencies to ensure that the worker
package is self-contained and our dependencies don't conflict with any that a
user might want to import into their notebook.

Most of what this module does is at precompilation time. It gathers the
dependencies of the vendored packages and saves their entry paths.  We encode
the entry points of each vendored package as a preference in the
`QuartoNotebookWorker` project file. This allows us to trigger recompilation of
the worker package when the vendored packages change since the paths passed as
preferences will change.
"""
module WorkerSetup

# Imports.

import Pkg
import RelocatableFolders
import Scratch
import TOML

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

# The loader environment is used to load the worker package into whatever
# environment that the user has started the process with.
const LOADER_ENV = Ref("")

# Since we start a task to perform the loader env setup at package init-time we
# don't want that to block `using QuartoNotebookRunner` so we lock the setup
# task to allow prevention of starting the loader env until
const WORKER_SETUP_LOCK = ReentrantLock()

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        LOADER_ENV[] = String(QNW)
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
            pushfirst!(LOAD_PATH, "@stdlib")
            import Pkg
            popfirst!(LOAD_PATH)

            cd($(repr(QNW)))

            pushfirst!(LOAD_PATH, $(repr(project)))
            Pkg.test("QuartoNotebookWorker")
            """,
        )
        julia = Base.julia_cmd()[1]
        cmd = `$julia $exeflags --startup-file=no $file`
        run(cmd)
    end
end

end
