# Diagnostic file logger activated by QUARTONOTEBOOKRUNNER_LOG env var.

mutable struct DiagnosticLogger <: Logging.AbstractLogger
    io::IO
    prefix::String
    function DiagnosticLogger(logdir::AbstractString, prefix::String)
        mkpath(logdir)
        logfile = joinpath(logdir, "$prefix-$(getpid()).log")
        io = open(logfile, "a")
        logger = new(io, prefix)
        finalizer(l -> close(l.io), logger)
        return logger
    end
end

Logging.min_enabled_level(::DiagnosticLogger) = Logging.Debug
Logging.shouldlog(::DiagnosticLogger, args...) = true
Logging.catch_exceptions(::DiagnosticLogger) = true

function Logging.handle_message(
    logger::DiagnosticLogger,
    level,
    message,
    _module,
    group,
    id,
    file,
    line;
    kwargs...,
)
    ts = Dates.format(Dates.now(), "HH:MM:SS.sss")
    lvl = uppercase(string(level))
    print(logger.io, ts, " [", lvl, "] ", logger.prefix, ": ", message)
    for (k, v) in kwargs
        if k === :exception && v isa Tuple
            ex, bt = v
            print(logger.io, "\n  ", k, " = ")
            showerror(logger.io, ex, bt)
        else
            print(logger.io, " ", k, "=", repr(v))
        end
    end
    println(logger.io)
    flush(logger.io)
end

function with_diagnostic_logger(f; prefix::String)
    logdir = get(ENV, "QUARTONOTEBOOKRUNNER_LOG", nothing)
    logdir === nothing && return f()
    logger = DiagnosticLogger(logdir, prefix)
    Logging.with_logger(f, logger)
end
