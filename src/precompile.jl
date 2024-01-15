PrecompileTools.@setup_workload begin
    notebook = joinpath(@__DIR__, "..", "test", "examples", "cell_types.qmd")
    script = joinpath(@__DIR__, "..", "test", "examples", "cell_types.jl")
    results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}()
    PrecompileTools.@compile_workload begin
        raw_text_chunks(notebook)
        raw_text_chunks(script)
        process_results(results)
    end
end
