PrecompileTools.@setup_workload begin
    notebook = joinpath(@__DIR__, "..", "test", "examples", "cell_types.qmd")
    script = joinpath(@__DIR__, "..", "test", "examples", "cell_types.jl")
    results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}()
    PrecompileTools.@compile_workload begin
        raw_text_chunks(notebook)
        raw_text_chunks(script)
        process_results(results)

        # find port to connect on
        port, _server = Sockets.listenany(8000)
        close(_server)
        server = QuartoNotebookRunner.serve(; port)

        sock = let
            connected = false
            for i = 1:20
                try
                    sock = Sockets.connect(port)
                    connected = true
                    break
                catch
                    sleep(0.1)
                end
            end
            connected || error("Connection could not be established.")
            sock
        end

        println(sock, """{"type":"isready","content":{}}""")
        @assert readline(sock) == "true"
        println(sock, """{"type":"isopen","content":"$(@__FILE__)"}""")
        @assert readline(sock) == "false"
        println(sock, """{"type":"stop","content":{}}""")
        wait(server)
    end
end
