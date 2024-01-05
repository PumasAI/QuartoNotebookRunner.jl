PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        server = Server()
        notebook = joinpath(@__DIR__, "..", "test", "examples", "cell_types.qmd")
        run!(server, notebook; output = IOBuffer(), showprogress = false)
        run!(server, notebook; output = IOBuffer(), showprogress = false)
        close!(server)
    end
end
