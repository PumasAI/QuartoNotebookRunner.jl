macro R_str(str)
    return esc(r_expr(str, __source__, __module__))
end
r_expr(code::AbstractString, src::LineNumberNode, mod::Module) =
    _r_expr(nothing, code, src, mod)
_r_expr(::Any, code::AbstractString, src, mod) = :(error("`RCall.jl` package not loaded."))
