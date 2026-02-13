# Worker process setup and configuration.

# Julia JLOptions code_coverage values (from Base)
const COVERAGE_USER = 1
const COVERAGE_ALL = 2
const COVERAGE_TRACKED = 3

"""
    _has_juliaup()

Check if juliaup is available on the system.
"""
function _has_juliaup()
    try
        success(`juliaup --version`) && success(`julia --version`)
    catch error
        return false
    end
end

"""
    _julia_exe(exeflags)

Determine the Julia executable and exeflags to use for worker processes.
Handles juliaup channels and QUARTO_JULIA environment variable.
"""
function _julia_exe(exeflags)
    # Find the `julia` executable to use for this worker process. If the
    # `juliaup` command is available, we can use plain `julia` if a channel has
    # been provided in the exeflags. The channel exeflag is dropped from the
    # exeflags vector so that it isn't provided twice, the second of which
    # would be treated as a file name.
    if _has_juliaup()
        indices = findall(startswith("+"), exeflags)
        if isempty(indices)
            quarto_julia = get(ENV, "QUARTO_JULIA", nothing)
            if isnothing(quarto_julia)
                # Use the default `julia` channel set for `juliaup`.
                return `julia`, exeflags
            else
                # Use the `julia` binary that was specified in the environment
                # variable that can be passed to `quarto` to pick the server
                # process `julia` to use.
                return `$quarto_julia`, exeflags
            end
        else
            # Pull out the channel from the exeflags. Since we merge in
            # exeflags from the `QUARTONOTEBOOKRUNNER_EXEFLAGS` environment
            # variable, we can't just drop the first element of the exeflags
            # since there may be more than one provided. Keep the last one.
            channel = exeflags[last(indices)]
            exeflags = exeflags[setdiff(1:end, indices)]
            return `julia $channel`, exeflags
        end
    end
    # Just use the current `julia` if there is no `juliaup` command available.
    bin = Base.julia_cmd()[1]
    return `$bin`, exeflags
end

"""
    _extract_timeout(merged_options)

Extract the daemon timeout value from options.
"""
function _extract_timeout(merged_options)
    daemon = something(merged_options["format"]["execute"]["daemon"], true)
    if daemon === true
        300.0 # match quarto's default timeout of 300 seconds
    elseif daemon === false
        0.0
    elseif daemon isa Real
        f = Float64(daemon)
        if f < 0
            throw(
                ArgumentError(
                    "Invalid execute.daemon value $f, must be a bool or a non-negative number (in seconds).",
                ),
            )
        end
        f
    else
        throw(
            ArgumentError(
                "Invalid execute.daemon value $daemon, must be a bool or a non-negative number (in seconds).",
            ),
        )
    end
end

"""
    _exeflags_and_env(options)

Extract and merge exeflags and environment variables for worker processes.
Handles QUARTONOTEBOOKRUNNER_EXEFLAGS, project settings, and coverage flags.
"""
function _exeflags_and_env(options)
    env_exeflags =
        JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_EXEFLAGS", "[]"), Vector{String})
    julia_config = julia_worker_config(options)
    # We want to be able to override exeflags that are defined via environment variable,
    # but leave the remaining flags intact (for example override number of threads but leave sysimage).
    # We can do this by adding the options exeflags after the env exeflags.
    # Julia will ignore earlier uses of the same flag.
    exeflags = [env_exeflags; julia_config.exeflags]
    env = julia_config.env
    # Use `--project=@.` if neither `JULIA_PROJECT=...` nor `--project=...` are specified
    if !any(startswith("JULIA_PROJECT="), env) && !any(startswith("--project="), exeflags)
        # Set it via the env variable since this is the "weakest" form of
        # setting it, which allows for an implicit `--project=` provided by a
        # custom linked `juliaup` channel to override it, e.g `julia
        # +CustomChannel` that is a link to `julia +channel --project=@global`.
        pushfirst!(env, "JULIA_PROJECT=@.")
    end
    # if exeflags already contains '--color=no', the 'no' will prevail
    pushfirst!(exeflags, "--color=yes")

    # Several QUARTO_* environment variables are passed to the worker process
    # via the `env` field rather than via real environment variables. Capture
    # these and pass them to the worker process separate from `env` since that
    # is used by the worker status printout and we don't want these extra ones
    # that the user has not set themselves to show up there.
    quarto_env = Base.byteenv(options["env"])

    # Set QUARTO_PROJECT_ROOT when Quarto provides a projectDir so that
    # the variable is refreshed for each project in multi-project renders.
    project_dir = get(options, "projectDir", nothing)
    if !isnothing(project_dir)
        push!(quarto_env, "QUARTO_PROJECT_ROOT=$project_dir")
    end

    # Ensure that coverage settings are passed to the worker so that worker
    # code is tracked correctly during tests.
    # Based on https://github.com/JuliaLang/julia/blob/eed18bdf706b7aab15b12f3ba0588e8fafcd4930/base/util.jl#L216-L229.
    opts = Base.JLOptions()
    if opts.code_coverage != 0
        # Forward the code-coverage flag only if applicable (if the filename
        # is pid-dependent)
        coverage_file =
            (opts.output_code_coverage != C_NULL) ?
            unsafe_string(opts.output_code_coverage) : ""
        if isempty(coverage_file) || occursin("%p", coverage_file)
            if opts.code_coverage == COVERAGE_USER
                push!(exeflags, "--code-coverage=user")
            elseif opts.code_coverage == COVERAGE_ALL
                push!(exeflags, "--code-coverage=all")
            elseif opts.code_coverage == COVERAGE_TRACKED
                push!(exeflags, "--code-coverage=@$(unsafe_string(opts.tracked_path))")
            end
            isempty(coverage_file) || push!(exeflags, "--code-coverage=$coverage_file")
        end
    end

    return exeflags, env, quarto_env
end
