module QuartoNotebookWorkerRCallExt

import QuartoNotebookWorker
import RCall

const RCall_temp_files_ref = Ref{String}()
const rcalljl_device_ref = Ref{Symbol}(:png)

function configure()
    for each in readdir(RCall_temp_files_ref[]; join = true)
        rm(each; force = true)
    end

    tmp_file_fmt = joinpath(RCall_temp_files_ref[], "rij_%03d")
    RCall.rcall_p(:options, rcalljl_filename = tmp_file_fmt)

    RCall.reval_p(RCall.rparse_p("""
        options(device = function(filename=getOption('rcalljl_filename'), ...) {
            args <- c(filename = filename, getOption('rcalljl_options'))
            do.call(getOption('rcalljl_device'), modifyList(args, list(...)))
        })
        """))

    fm = QuartoNotebookWorker._figure_metadata()

    rcalljl_device = fm.fig_format == "pdf" ? :png : Symbol(fm.fig_format)
    rcalljl_device in (:png, :svg) || (rcalljl_device = :png)
    rcalljl_device_ref[] = rcalljl_device

    width_inches = fm.fig_width_inch !== nothing ? fm.fig_width_inch : 6
    height_inches = fm.fig_height_inch !== nothing ? fm.fig_height_inch : 5
    dpi = fm.fig_dpi !== nothing ? fm.fig_dpi : 96

    RCall.rcall_p(:options; rcalljl_device)
    RCall.rcall_p(
        :options,
        rcalljl_options = Dict(
            :width => width_inches * dpi,
            :height => height_inches * dpi,
        ),
    )

    return nothing
end

function display_plots()
    if RCall.rcopy(Int, RCall.rcall_p(Symbol("dev.cur"))) != 1
        render_type =
            rcalljl_device_ref[] === :png ? QuartoNotebookWorker.PNG :
            QuartoNotebookWorker.SVG
        RCall.rcall_p(Symbol("dev.off"))
        for fn in sort(readdir(RCall_temp_files_ref[]; join = true))
            open(fn) do io
                display(render_type(read(io)))
            end
            rm(fn)
        end
    end
end

function cleanup_temp_files()
    if RCall.rcopy(Int, RCall.rcall_p(Symbol("dev.cur"))) != 1
        RCall.rcall_p(Symbol("dev.off"))
    end
    for fn in readdir(RCall_temp_files_ref[]; join = true)
        rm(fn)
    end
end

function refresh()
    # Remove all variables from the session, this does not detach loaded
    # libraries but we don't unload libraries in julia either to save time.
    RCall.reval_p(RCall.rparse_p("rm(list = ls(all.names = TRUE))"))
end

function __init__()
    RCall_temp_files_ref[] = mktempdir()
    configure()
    QuartoNotebookWorker.add_package_loading_hook!(configure)
    QuartoNotebookWorker.add_package_refresh_hook!(refresh)
    QuartoNotebookWorker.add_post_eval_hook(display_plots)
    QuartoNotebookWorker.add_post_error_hook(cleanup_temp_files)
end

end
