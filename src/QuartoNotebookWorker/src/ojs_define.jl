"""
    ojs_define(; kwargs...)

Given a list of `name = object` pairs, makes them available to *ObservableJS*
by rendering their HTML/JavaScript representation.
"""
function ojs_define(; kwargs...)
    json_write = _json_writer()
    if isnothing(json_write)
        @warn "No JSON package imported. Please import either JSON.jl or JSON3.jl to use `ojs_define`."
        return nothing
    else
        object = ojs_convert(kwargs)
        return HTML() do io
            write(io, "<script type='ojs-define'>")
            json_write(io, Dict("contents" => object))
            write(io, "</script>")
        end
    end
end

# JSON package interfaces. Functions are extended with methods in their
# respective extensions (QuartoNotebookWorkerJSONExt and
# QuartoNotebookWorkerJSON3Ext). Returns a suitable writer function.

_json_writer() = _json3_write(nothing)

# Prioritize JSON3 over JSON. First check whether there is a suitable
# `_json3_write`, and if not defined then check `_json_write`. Default
# returns `nothing` which signals that there is no suitable writer.
_json3_write(::Any) = _json_write(nothing)
_json_write(::Any) = nothing

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
