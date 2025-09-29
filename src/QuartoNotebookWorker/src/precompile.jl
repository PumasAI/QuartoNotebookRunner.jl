precompile(Tuple{typeof(QuartoNotebookWorker.Malt.main)})
precompile(Tuple{typeof(QuartoNotebookWorker.Malt._bson_deserialize), QuartoNotebookWorker.Malt.Sockets.TCPSocket})

for type in [Int,Float64,String,Nothing,Missing]
    precompile(
        Tuple{
            typeof(Core.kwcall),
            NamedTuple{(:inline,), Tuple{Bool}},
            typeof(QuartoNotebookWorker.render_mimetypes),
            type,
            Base.Dict{String, Any}
        }
    )
end

precompile(Tuple{typeof(Base.Filesystem.mkpath), String})
precompile(Tuple{typeof(QuartoNotebookWorker.refresh!), Base.Dict{String, Any}})
precompile(Tuple{typeof(QuartoNotebookWorker.refresh!), Base.Dict{String, Any}, Base.Dict{String, Any}})
precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:file, :line, :cell_options), Tuple{String, Int64, Base.Dict{String, Any}}}, typeof(QuartoNotebookWorker.include_str), Module, String})

module __PrecompilationModule end

QuartoNotebookWorker.NotebookState.NotebookModuleForPrecompile[] = __PrecompilationModule

PrecompileTools.@compile_workload begin
    result = QuartoNotebookWorker.render(
        "1 + 1",
        "some_file",
        1,
        Dict{String,Any}();
        inline = false,
    )
    io = IOBuffer()
    bson = QuartoNotebookWorker.Packages.BSON.bson(io, Dict{Symbol,Any}(:data => result))
    seekstart(io)
    QuartoNotebookWorker.Packages.BSON.load(io)[:data]
end

QuartoNotebookWorker.NotebookState.NotebookModuleForPrecompile[] = nothing