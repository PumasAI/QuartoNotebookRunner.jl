macro py_str(str)
    return esc(py_expr(str, __source__, __module__))
end
py_expr(code::AbstractString, src::LineNumberNode, mod::Module) =
    _py_expr(nothing, code, src, mod)
_py_expr(::Any, code::AbstractString, src, mod) =
    :(error("`PythonCall.jl` package not loaded."))
