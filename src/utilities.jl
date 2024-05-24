"""
    test_pr(cmd::Cmd; url::String, rev::String)

Test a PR by running the given command with the PR's changes. `url` defaults to
the `QuartoNotebookRunner.jl` repo. `rev` is required, and should be the branch
name of the PR. `cmd` should be the `quarto render` command to run.
"""
function test_pr(
    cmd::Cmd;
    url::String = "https://github.com/PumasAI/QuartoNotebookRunner.jl",
    rev::String,
)
    # Require the user to already have a `quarto` install on their path.
    quarto = Sys.which("quarto")
    if isnothing(quarto)
        error("Quarto not found. Please install Quarto.")
    end

    # We require at least v1.5.29 to run this backend.
    version = VersionNumber(readchomp(`quarto --version`))
    if version < v"1.5.29"
        error(
            "Quarto version $version is not supported. Please upgrade to at least v1.5.29.",
        )
    end

    # Ensure that any running server is stopped before we start.
    _stop_running_server() || error("Failed to stop the running server.")

    mktempdir() do dir
        file = joinpath(dir, "file.jl")
        write(
            file,
            """
            import Pkg
            Pkg.add(; url = $(repr(url)), rev = $(repr(rev)))
            """,
        )
        run(`$(Base.julia_cmd()) --startup-file=no --project=$dir $file`)
        run(addenv(`$cmd --execute-debug`, "QUARTO_JULIA_PROJECT" => dir))
    end
end

function _stop_running_server()
    cache_dir = _quarto_julia_cache_dir()
    transport_file = joinpath(cache_dir, "julia_transport.txt")
    if isfile(transport_file)
        @info "Removing transport file." transport_file

        json = open(JSON3.read, transport_file)
        pid = get(json, "pid", nothing)
        try
            _kill_proc(pid)
        catch error
            @error "Failed to stop the running server." error transport_file pid
            return false
        end
        try
            rm(transport_file)
        catch error
            @error "Failed to remove the transport file." error transport_file
            return false
        end
    else
        @info "No transport file found."
    end
    return true
end

function _kill_proc(id::Integer)
    if Sys.iswindows()
        run(`taskkill /F /PID $id`)
    else
        run(`kill -9 $id`)
    end
end

function _quarto_julia_cache_dir()
    home = homedir()
    if Sys.isapple()
        path = joinpath(home, "Library", "Caches", "quarto", "julia")
        isdir(path) && return path
    elseif Sys.iswindows()
        localappdata = get(ENV, "LOCALAPPDATA", nothing)
        if !isnothing(localappdata)
            path = joinpath(localappdata, "quarto", "julia")
            isdir(path) && return path
        end

        appdata = get(ENV, "APPDATA", nothing)
        if !isnothing(appdata)
            path = joinpath(appdata, "quarto", "julia")
            isdir(path) && return path
        end
    elseif Sys.islinux()
        xdg_cache_home = get(ENV, "XDG_CACHE_HOME", nothing)
        if !isnothing(xdg_cache_home)
            path = joinpath(xdg_cache_home, ".cache", "quarto", "julia")
            isdir(path) && return path
        end

        path = joinpath(home, ".cache", "quarto", "julia")
        isdir(path) && return path
    else
        error("Unsupported OS.")
    end

    error("Could not find a suitable cache directory.")
end
