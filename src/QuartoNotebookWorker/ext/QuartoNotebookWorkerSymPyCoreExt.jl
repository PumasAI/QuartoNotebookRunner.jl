module QuartoNotebookWorkerSymPyCoreExt

import QuartoNotebookWorker as QNW
import ..SymPyCore as SPC

QNW._mimetype_wrapper(s::SPC.SymbolicObject) = SymWrapper(s)
QNW._mimetype_wrapper(s::AbstractArray{<:SPC.Sym}) = SymWrapper(s)
QNW._mimetype_wrapper(s::Dict{T,S}) where {T<:SPC.SymbolicObject,S<:Any} = SymWrapper(s)

struct SymWrapper <: QNW.WrapperType
    value::Any
end

Base.show(io::IO, ::MIME"text/markdown", s::SymWrapper) = show(io, "text/latex", s.value)
Base.showable(::MIME"text/markdown", ::SymWrapper) = true

end
