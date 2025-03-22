module QuartoNotebookWorkerLaTeXStringsExt

import QuartoNotebookWorker as QNW
import LaTeXStrings as LS

QNW._mimetype_wrapper(s::LS.LaTeXString) = LaTeXStringWrapper(s)

struct LaTeXStringWrapper <: QNW.WrapperType
    value::LS.LaTeXString
end

function Base.show(io::IO, ::MIME"text/markdown", s::LaTeXStringWrapper)
    qnr = get(io, :QuartoNotebookRunner, nothing)
    isnothing(qnr) && error("No QuartoNotebookRunner found in IO context")
    to_format = QNW.rget(qnr.options, ("format", "pandoc", "to"), nothing)
    # Workaround for some weirdness in the treatment of rendering for math in
    # typst output which fails to render display maths if it doesn't have to
    # correct leading and trailing dollars. PDF(tex) output requires that
    # `\begin` blocks don't have `$$` wrappers, but typst requires them.
    wrap = to_format == "typst" && !qnr.inline && !startswith(s.value, "\$")
    wrap && print(io, "\$\$")
    show(io, MIME("text/latex"), s.value)
    wrap && print(io, "\$\$")
end
Base.showable(::MIME"text/markdown", ::LaTeXStringWrapper) = true

end
