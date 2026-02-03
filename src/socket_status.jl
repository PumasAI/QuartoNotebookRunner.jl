# Server status formatting for socket interface.

"""
    is_same_day(date1, date2)

Check if two dates fall on the same calendar day.
"""
function is_same_day(date1, date2)::Bool
    return Dates.year(date1) == Dates.year(date2) &&
           Dates.month(date1) == Dates.month(date2) &&
           Dates.day(date1) == Dates.day(date2)
end

"""
    simple_date_time_string(date)

Format a datetime for display, showing time only if same day.
"""
function simple_date_time_string(date)::String
    now = Dates.now()
    if is_same_day(date, now)
        return string(Dates.hour(date), ":", Dates.minute(date), ":", Dates.second(date))
    else
        return string(
            date,
            " ",
            Dates.hour(date),
            ":",
            Dates.minute(date),
            ":",
            Dates.second(date),
        )
    end
end

"""
    format_seconds(seconds)

Format a duration in seconds as human-readable string.
"""
function format_seconds(seconds)::String
    seconds = round(Int, seconds)
    if seconds < 60
        return string(seconds, " second", seconds == 1 ? "" : "s")
    elseif seconds < 3600
        full_minutes = div(seconds, 60)
        rem_seconds = seconds % 60
        seconds_str = rem_seconds == 0 ? "" : " " * format_seconds(rem_seconds)
        return string(full_minutes, " minute", full_minutes == 1 ? "" : "s", seconds_str)
    else
        full_hours = div(seconds, 3600)
        rem_seconds = seconds % 3600
        minutes_str = rem_seconds == 0 ? "" : " " * format_seconds(rem_seconds)
        return string(full_hours, " hour", full_hours == 1 ? "" : "s", minutes_str)
    end
end

"""
    server_status(socketserver::SocketServer)

Generate a detailed status report for the socket server and its workers.
"""
function server_status(socketserver::SocketServer)
    server_timeout = socketserver.timeout
    timeout_started_at = socketserver.timeout_started_at[]
    server = socketserver.notebookserver
    lock(server.lock) do
        io = IOBuffer()
        current_time = Dates.now()

        running_since_seconds = Dates.value(current_time - socketserver.started_at) / 1000

        println(io, "QuartoNotebookRunner server status:")
        println(
            io,
            "  started at: $(simple_date_time_string(socketserver.started_at)) ($(format_seconds(running_since_seconds)) ago)",
        )
        println(io, "  runner version: $QNR_VERSION")
        println(
            io,
            "  environment: $(replace(Base.active_project(), "Project.toml" => ""))",
        )
        println(io, "  pid: $(Base.getpid())")
        println(io, "  port: $(socketserver.port)")
        println(io, "  julia version: $(VERSION)")

        print(
            io,
            "  timeout: $(server_timeout === nothing ? "disabled" : format_seconds(server_timeout))",
        )

        if isempty(server.workers) &&
           server_timeout !== nothing &&
           timeout_started_at !== nothing
            seconds_until_server_timeout =
                server_timeout - Dates.value(Dates.now() - timeout_started_at) / 1000
            println(io, " ($(format_seconds(seconds_until_server_timeout)) left)")
        else
            println(io)
        end

        println(io, "  workers active: $(length(server.workers))")

        for (index, file) in enumerate(values(server.workers))
            run_started = file.run_started
            run_finished = file.run_finished

            if isnothing(run_started)
                seconds_since_started = nothing
            else
                seconds_since_started = Dates.value(current_time - run_started) / 1000
            end

            if isnothing(run_started) || isnothing(run_finished)
                run_duration_seconds = nothing
            else
                run_duration_seconds = Dates.value(run_finished - run_started) / 1000
            end

            if isnothing(run_finished)
                seconds_since_finished = nothing
            else
                seconds_since_finished = Dates.value(current_time - run_finished) / 1000
            end

            if file.timeout > 0 && !isnothing(seconds_since_finished)
                time_until_timeout = file.timeout - seconds_since_finished
            else
                time_until_timeout = nothing
            end

            run_started_str =
                isnothing(run_started) ? "-" : simple_date_time_string(run_started)
            run_started_ago =
                isnothing(seconds_since_started) ? "" :
                " ($(format_seconds(seconds_since_started)) ago)"

            run_finished_str =
                isnothing(run_finished) ? "-" : simple_date_time_string(run_finished)
            run_duration_str =
                isnothing(run_duration_seconds) ? "" :
                " (took $(format_seconds(run_duration_seconds)))"

            timeout_str = "$(format_seconds(file.timeout))"
            time_until_timeout_str =
                isnothing(time_until_timeout) ? "" :
                " ($(format_seconds(time_until_timeout)) left)"

            println(io, "    worker $(index):")
            println(io, "      path: $(file.path)")
            println(io, "      run started: $(run_started_str)$(run_started_ago)")
            println(io, "      run finished: $(run_finished_str)$(run_duration_str)")
            println(io, "      timeout: $(timeout_str)$(time_until_timeout_str)")
            println(io, "      pid: $(file.worker.proc_pid)")
            println(io, "      exe: $(file.exe)")
            println(io, "      exeflags: $(file.exeflags)")
            println(io, "      env: $(file.env)")
        end

        return String(take!(io))
    end
end
