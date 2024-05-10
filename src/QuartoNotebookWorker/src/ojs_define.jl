# TODO: move to a package extension.

function ojs_define(; kwargs...)
    json_id = Base.PkgId(Base.UUID("682c06a0-de6a-54ab-a142-c8b1cf79cde6"), "JSON")
    dataframes_id =
        Base.PkgId(Base.UUID("a93c6f00-e57d-5684-b7b6-d8193f3e46c0"), "DataFrames")
    tables_id = Base.PkgId(Base.UUID("5d742f6a-9f54-50ce-8119-136d35baa42b"), "Tables")

    if haskey(Base.loaded_modules, json_id)
        JSON = Base.loaded_modules[json_id]
        contents =
            if haskey(Base.loaded_modules, dataframes_id) &&
               haskey(Base.loaded_modules, tables_id)
                DataFrames = Base.loaded_modules[dataframes_id]
                Tables = Base.loaded_modules[tables_id]
                conv(x) = isa(x, DataFrames.AbstractDataFrame) ? Tables.rows(x) : x
                [Dict("name" => k, "value" => conv(v)) for (k, v) in kwargs]
            else
                [Dict("name" => k, "value" => v) for (k, v) in kwargs]
            end
        json = JSON.json(Dict("contents" => contents))
        return HTML("<script type='ojs-define'>$(json)</script>")
    else
        @warn "JSON package not available. Please install the JSON.jl package to use ojs_define."
        return nothing
    end
end
