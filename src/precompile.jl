PrecompileTools.@setup_workload begin
    notebook = joinpath(@__DIR__, "..", "test", "examples", "cell_types.qmd")
    script = joinpath(@__DIR__, "..", "test", "examples", "cell_types.jl")
    results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}()
    PrecompileTools.@compile_workload begin
        raw_text_chunks(notebook)
        raw_text_chunks(script)
        process_results(results)

        server = QuartoNotebookRunner.serve()
        sock = Sockets.connect(server.port)

        QuartoNotebookRunner._write_hmac_json(
            sock,
            server.key,
            Dict(:type => "isready", :content => Dict()),
        )
        @assert readline(sock) == "true"

        QuartoNotebookRunner._write_hmac_json(
            sock,
            server.key,
            Dict(:type => "isopen", :content => @__FILE__),
        ) # just to have any absolute file path that exists but is not open
        @assert readline(sock) == "false"

        QuartoNotebookRunner._write_hmac_json(
            sock,
            server.key,
            Dict(:type => "stop", :content => Dict()),
        )
        wait(server)
    end
end
