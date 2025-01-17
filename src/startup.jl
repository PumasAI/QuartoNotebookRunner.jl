# This script acts as the loader for the `QuartoNotebookWorker` package as well
# as the worker socket server initializer.

# Step 1:
#
# Inject a sandbox environment into the `LOAD_PATH` such that it gets picked up
# as the active project if there isn't one found in the rest of the
# `LOAD_PATH`.
#
# It needs to appear ahead of the `QuartoNotebookWorker` environment so that it
# shadows that environment since that is not a user-facing project directory,
# and if a user was to perform `Pkg` operations they may affect that
# environment. Instead we provide a temporary sandbox environment that gets
# discarded when the notebook process exits.
let sandbox = joinpath(mktempdir(), "QuartoSandbox")
    mkpath(sandbox)
    # The empty project file is key to making this the active environment if
    # noting else is available if the rest of the `LOAD_PATH`.
    touch(joinpath(sandbox, "Project.toml"))
    push!(LOAD_PATH, sandbox)
end

# Step 2:
#
# This contains the worker package environment. It gets added to the LOAD_PATH
# so that we can `require` it further down this file.
push!(LOAD_PATH, ENV["QUARTONOTEBOOKWORKER_PACKAGE"])

# Step 3:
#
# We also need to ensure that `@stdlib` is available on the LOAD_PATH so that
# requiring the worker package does not attempt to load stdlib packages from
# the wrong `julia` version. The errors that get thrown when this happens look
# like deserialization errors due to differences in struct definitions, or
# method signatures between different versions of Julia. This happens with
# running `Pkg.test`, which drops `@stdlib` from the load path, but does not
# happen if using `TestEnv.jl` to run tests in a REPL session via `include`.
pushfirst!(LOAD_PATH, "@stdlib")

# Step 4:
#
# Writes the error and stacktrace to the parent-provided log file rather than
# stderr. An alternative would be to capture stderr from the parent when
# starting this process, but then that swallows all stderr from then on. We
# only want to capture these two potential errors during startup, all others
# can later be routed to the parent process since we have a socket open by that
# point.
function capture(func)
    try
        return func()
    catch err
        errors_log_file = joinpath(ENV["MALT_WORKER_TEMP_DIR"], "errors.log")
        open(errors_log_file, "w") do io
            showerror(io, err)
            Base.show_backtrace(io, catch_backtrace())
            flush(io)
        end
        exit()
    end
end

# Step 5:
#
# The parent process needs some additional metadata about this `julia` process to
# be able to provide relevant error messages to the user.
#
# Currently we collect the Julia version, as well as the paths to the project
# and manifest files if they are available. These are printed to the
# `metadata.toml` file in TOML format. We avoid using the `TOML` stdlib and
# instead manually write the strings so that this can happen prior to any
# stdlib loading, which could trigger errors that we would then want this
# metadata to be able to properly inform the user about.
capture() do
    metadata_toml_file = joinpath(ENV["MALT_WORKER_TEMP_DIR"], "metadata.toml")
    open(metadata_toml_file, "w") do io
        project_toml_file = Base.active_project()
        if !isnothing(project_toml_file) && isfile(project_toml_file)
            println(io, "project = $(repr(project_toml_file))")
            manifest_toml_file = Base.project_file_manifest_path(project_toml_file)
            if !isnothing(manifest_toml_file) && isfile(manifest_toml_file)
                println(io, "manifest = $(repr(manifest_toml_file))")
            end
        end
        println(io, "julia_version = $(repr(string(VERSION)))")
        flush(io)
    end
end

# Step 6:
#
# Now load in the worker package. This may trigger package precompilation on
# first load, hence it is run under a `capture` should it fail to run.
const QuartoNotebookWorker = capture() do
    Base.require(
        Base.PkgId(
            Base.UUID("38328d9c-a911-4051-bc06-3f7f556ffeda"),
            "QuartoNotebookWorker",
        ),
    )
end

# Step 7:
#
# Ensures that the LOAD_PATH is returned to it's previous state without the
# `@stdlib` that was pushed to it near the start of the file.
popfirst!(LOAD_PATH)

# Step 8:
#
# This calls into the main socket server loop, which does not terminate until
# the process is finished off and the notebook needs closing. So anything
# written after this call is "cleanup" code. "Setup" code all needs to appear
# before this call.
capture(QuartoNotebookWorker.Malt.main)
