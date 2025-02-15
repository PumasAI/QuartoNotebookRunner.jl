macro py_str(str)
    return esc(py_expr(str))
end
py_expr(code::AbstractString) = _py_expr(nothing, code)
_py_expr(::Any, code::AbstractString) = :(error("`PythonCall.jl` package not loaded."))
