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

        JSON3.write(sock, Dict(:type => "isready", :content => Dict()))
        println(sock)
        @assert readline(sock) == "true"

        JSON3.write(sock, Dict(:type => "isopen", :content => @__FILE__)) # just to have any absolute file path that exists but is not open
        println(sock)
        @assert readline(sock) == "false"

        JSON3.write(sock, Dict(:type => "stop", :content => Dict()))
        println(sock)
        wait(server)
    end
end
