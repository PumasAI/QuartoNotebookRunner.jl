struct OJSDefine end

ojs_define(; kwargs...) = _ojs_define(OJSDefine(), kwargs)

function _ojs_define(::Any, kwargs)
    @warn "JSON package not available. Please install the JSON.jl package to use ojs_define."
    return nothing
end

ojs_convert(kwargs) = [Dict("name" => k, "value" => _ojs_convert(v)) for (k, v) in kwargs]

_istable(x) = __istable(nothing, x)
__istable(::Any, x) = false

_rows(x) = __rows(nothing, x)
__rows(::Any, x) = error("Object does not support `Tables.rows` interface.")

# Enumerate all rows if the object supports rowtable inferface.
_ojs_convert(x) = _istable(x) ? _rows(x) : x
