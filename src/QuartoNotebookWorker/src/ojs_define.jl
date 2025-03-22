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

# Internal function to check if the object supports a specific trait.
# QuartoNotebookWorker extensions that implement specific traits
# should override this function.
# The fallback implementation reports no trait support.
_has_trait(trait::Val, obj::Any) = false

# Trait-specific object conversion that is called when the object
# supports a specific trait (_has_trait(trait, obj) == true).
# QuartoNotebookWorker extensions that implement specific traits
# should override this function.
# The fallback implementation returns the object unchanged.
_ojs_convert(trait::Val, obj::Any) = obj

# The default object conversion function that is called when
# there is no more specific _ojs_convert(obj::T)
function _ojs_convert(obj::Any)
    # check if the object implements any of the traits supported by extensions
    if _has_trait(Val(:table), obj)
        # if QuartoNotebookWorkerTablesExt is active and
        # obj supports Tables.istable(obj) interface, do table-specific conversion
        return _ojs_convert(Val(:table), obj)
    else
        # no specific trait support, no conversion by default
        return obj
    end
end
