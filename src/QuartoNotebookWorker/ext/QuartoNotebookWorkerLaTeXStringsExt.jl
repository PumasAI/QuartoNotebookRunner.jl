module QuartoNotebookWorkerLaTeXStringsExt

import QuartoNotebookWorker as QNW
import ..LaTeXStrings as LS

QNW._mimetype_wrapper(s::LS.LaTeXString) = LaTeXStringWrapper(s)

struct LaTeXStringWrapper <: QNW.WrapperType
    value::LS.LaTeXString
end

Base.show(io::IO, ::MIME"text/markdown", s::LaTeXStringWrapper) = print(io, s.value)
Base.showable(::MIME"text/markdown", ::LaTeXStringWrapper) = true

end
