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

import RelocatableFolders

# Support adding to a system image.
const QNW = RelocatableFolders.@path joinpath(@__DIR__, "QuartoNotebookWorker")

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
    mktempdir() do temp_dir
        julia = Base.julia_cmd()[1]
        debug_env = joinpath(temp_dir, "QuartoNotebookWorker.DEBUG")
        cmd = `$julia $exeflags --project=$debug_env --startup-file=no -i $DEBUG_STARTUP`
        run(addenv(cmd, "QUARTONOTEBOOKWORKER_PACKAGE" => String(QNW)))
    end
end
const DEBUG_STARTUP = RelocatableFolders.@path joinpath(@__DIR__, "debug_startup.jl")

"""
    test()

Run the test suite for `QuartoNotebookWorker`. This is run in isolation from the
current process. If you want to run the tests interactively use `debug()` and
the `TestEnv` package to do so.
"""
function test(; exeflags = String[])
    mktempdir() do temp_dir
        julia = Base.julia_cmd()[1]
        test_env = joinpath(temp_dir, "QuartoNotebookWorker.TEST")
        cmd = `$julia $exeflags --project=$test_env --startup-file=no $TEST_STARTUP`
        run(addenv(cmd, "QUARTONOTEBOOKWORKER_PACKAGE" => String(QNW)))
    end
end
const TEST_STARTUP = RelocatableFolders.@path joinpath(@__DIR__, "test_startup.jl")

end
