struct OJSDefine end

"""
    ojs_define(; kwargs...)

User-facing function that, given a list of `name = object` pairs,
makes them available to *ObservableJS* by rendering their
HTML/JavaScript representation.
"""
ojs_define(; kwargs...) = _ojs_define(OJSDefine(), kwargs)

# Internal function that implements rendering of the `name = object` pairs.
# The actual implementation is in the QuartoNotebookWorkerJSONExt extension.
function _ojs_define(::Any, kwargs)
    @warn "JSON package not available. Please install the JSON.jl package to use ojs_define."
    return nothing
end

"""
    ojs_convert(kwargs)

Given an iterator of `name => object` pairs, return a vector of
`Dict("name" => name, "value" => lowered_object)`, where the `lowered_object`
(the result of `_ojs_convert(object)`) is the `object` representation
that supports direct conversion to JSON.
"""
ojs_convert(kwargs) = [Dict("name" => k, "value" => _ojs_convert(v)) for (k, v) in kwargs]

# Internal function to check if the object supports Tables.jl table interface
# QuartoNotebookWorkerTablesExt overrides this function with the actual implementation.
# The fallback implementation reports no table interace support.
_istable(::Any, obj::Any) = false
# outer function called from _ojs_convert()
_istable(obj::Any) = _istable(nothing, obj)

# Get rows iterator for objects that support Tables.jl table interface
# (see _istable()) to facilitate OJS conversion.
# QuartoNotebookWorkerTablesExt overrides this function with the actual implementation.
# The fallback implementation throws an error.
_ojs_rows(::Any, obj::Any) = error("Object does not support `Tables.rows` interface.")
# outer function called from _ojs_convert()
_ojs_rows(obj::Any) = _ojs_rows(nothing, obj)

# The default object conversion function that is called when
# there is no more specific _ojs_convert(obj::T)
function _ojs_convert(obj::Any)
    # check if the object implements any of the traits supported by extensions
    if _istable(obj)
        # if QuartoNotebookWorkerTablesExt is active and
        # obj supports Tables.istable(obj) interface, do table-specific conversion
        return _ojs_rows(obj)
    else
        # no specific trait support, no conversion by default
        return obj
    end
end
