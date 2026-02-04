# IO capture and context for cell evaluation.

function io_capture(f; cell_options, kws...)
    warning = get(cell_options, "warning", true)
    capture() = Packages.IOCapture.capture(f; kws...)
    if warning
        return capture()
    else
        logger = Logging.global_logger()
        current_level = Logging.min_enabled_level(logger)
        try
            Logging.disable_logging(Logging.Error)
            return capture()
        finally
            Logging.disable_logging(current_level - 1)
        end
    end
end

# passing our module removes Main.Notebook noise when printing types etc.
function with_context(io::IO, cell_options = Dict{String,Any}(), inline = false)
    return IOContext(io, _io_context(cell_options, inline)...)
end

function _io_context(cell_options = Dict{String,Any}(), inline = false)
    return [
        :module => NotebookState.notebook_module(),
        :limit => true,
        :color => Base.have_color,
        # This allows a `show` method implementation to check for
        # metadata that may be of relevance to it's rendering. For
        # example, if a `typst` table is rendered with a caption
        # (available in the `cell_options`) then we need to adjust the
        # syntax that is output via the `QuartoNotebookRunner/typst`
        # show method to switch between `markdown` and `code` "mode".
        #
        # TODO: perhaps preprocess the metadata provided here rather
        # than just passing it through as-is.
        :QuartoNotebookRunner =>
            (; cell_options, options = NotebookState.OPTIONS[], inline),
    ]
end
