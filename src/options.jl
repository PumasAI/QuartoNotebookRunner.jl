# Notebook options handling and frontmatter parsing.

"""
    _recursive_merge(x...)

Recursively merge dictionaries, with later values overriding earlier ones.
"""
_recursive_merge(x::AbstractDict...) = merge(_recursive_merge, x...)
_recursive_merge(x...) = x[end]

"""
    default_frontmatter()

Return default frontmatter settings for notebooks.
"""
function default_frontmatter()
    D = Dict{String,Any}
    env = JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_ENV", "[]"), Vector{String})
    return D(
        "fig-format" => "png",
        "julia" => D("env" => env, "exeflags" => []),
        "execute" => D("error" => true),
    )
end

"""
    _parsed_options(options)

Parse options from a file path or return as-is if already a Dict.
"""
function _parsed_options(options::String)
    isfile(options) || error("`options` is not a valid file: $(repr(options))")
    open(options) do io
        return JSON3.read(io, Any)
    end
end
_parsed_options(options::Dict{String,Any}) = options

"""
    julia_worker_config(options)

Extract Julia worker configuration (exeflags, env) from nested options.
"""
function julia_worker_config(options::Dict)
    meta = get(get(get(options, "format", Dict()), "metadata", Dict()), "julia", Dict())
    (
        exeflags = map(String, get(meta, "exeflags", String[])),
        env = map(String, get(meta, "env", String[])),
        strict_manifest_versions = get(meta, "strict_manifest_versions", false),
        share_worker_process = get(meta, "share_worker_process", false),
    )
end

"""
    _options_template(; kwargs...)

Create a standardized options dictionary structure.
"""
function _options_template(;
    fig_width,
    fig_height,
    fig_format,
    fig_dpi,
    error,
    eval,
    pandoc_to,
    julia,
    daemon,
    params,
    cache,
    env,
    cwd,
    project_dir,
)
    D = Dict{String,Any}
    return D(
        "format" => D(
            "execute" => D(
                "fig-width" => fig_width,
                "fig-height" => fig_height,
                "fig-format" => fig_format,
                "fig-dpi" => fig_dpi,
                "error" => error,
                "eval" => eval,
                "daemon" => daemon,
                "cache" => cache,
            ),
            "pandoc" => D("to" => pandoc_to),
            "metadata" => D("julia" => julia),
        ),
        "params" => D(params),
        "env" => env,
        "cwd" => cwd,
        "projectDir" => project_dir,
    )
end

"""
    _extract_relevant_options(file_frontmatter, options)

Merge file frontmatter with runtime options into standardized format.
"""
function _extract_relevant_options(file_frontmatter::Dict, options::Dict)
    D = Dict{String,Any}

    file_frontmatter = _recursive_merge(default_frontmatter(), file_frontmatter)

    fig_width_default = get(file_frontmatter, "fig-width", nothing)
    fig_height_default = get(file_frontmatter, "fig-height", nothing)
    fig_format_default = get(file_frontmatter, "fig-format", nothing)
    fig_dpi_default = get(file_frontmatter, "fig-dpi", nothing)
    error_default = get(get(D, file_frontmatter, "execute"), "error", true)
    eval_default = get(get(D, file_frontmatter, "execute"), "eval", true)
    daemon_default = get(get(D, file_frontmatter, "execute"), "daemon", true)
    cache_default = get(get(D, file_frontmatter, "execute"), "cache", false)

    pandoc_to_default = nothing

    julia_default = get(file_frontmatter, "julia", nothing)

    params_default = get(file_frontmatter, "params", Dict{String,Any}())

    if isempty(options)
        return _options_template(;
            fig_width = fig_width_default,
            fig_height = fig_height_default,
            fig_format = fig_format_default,
            fig_dpi = fig_dpi_default,
            error = error_default,
            eval = eval_default,
            pandoc_to = pandoc_to_default,
            julia = julia_default,
            daemon = daemon_default,
            params = params_default,
            cache = cache_default,
            env = Dict{String,Any}(),
            cwd = nothing,
            project_dir = nothing,
        )
    else
        format = get(D, options, "format")
        env = get(D, options, "env")
        execute = get(D, format, "execute")
        fig_width = get(execute, "fig-width", fig_width_default)
        fig_height = get(execute, "fig-height", fig_height_default)
        fig_format = get(execute, "fig-format", fig_format_default)
        fig_dpi = get(execute, "fig-dpi", fig_dpi_default)
        error = get(execute, "error", error_default)
        eval = get(execute, "eval", eval_default)
        daemon = get(execute, "daemon", daemon_default)
        cache = get(execute, "cache", cache_default)

        pandoc = get(D, format, "pandoc")
        pandoc_to = get(pandoc, "to", pandoc_to_default)

        metadata = get(D, format, "metadata")
        julia = get(metadata, "julia", Dict())
        julia_merged = _recursive_merge(julia_default, julia)

        # quarto stores params in two places currently, in `format.metadata.params` we have params specified in the front matter
        # and in top-level `params` we have the parameters via command-line arguments.
        # In case quarto decides to unify this behavior later, we probably can stop merging these on our side.
        # Cf. https://github.com/quarto-dev/quarto-cli/issues/9197
        params = get(metadata, "params", Dict())
        cli_params = get(options, "params", Dict())
        params_merged = _recursive_merge(params_default, params, cli_params)

        cwd = get(options, "cwd", nothing)
        project_dir = get(options, "projectDir", nothing)

        return _options_template(;
            fig_width,
            fig_height,
            fig_format,
            fig_dpi,
            error,
            eval,
            pandoc_to,
            julia = julia_merged,
            daemon,
            params = params_merged,
            cache,
            env,
            cwd,
            project_dir,
        )
    end
end
