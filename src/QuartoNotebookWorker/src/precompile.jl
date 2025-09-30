precompile(Tuple{typeof(QuartoNotebookWorker.Malt.main)})
precompile(Tuple{typeof(QuartoNotebookWorker.Malt._bson_deserialize), QuartoNotebookWorker.Malt.Sockets.TCPSocket})

if VERSION >= v"1.9"
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
    precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:file, :line, :cell_options), Tuple{String, Int64, Base.Dict{String, Any}}}, typeof(QuartoNotebookWorker.include_str), Module, String})
end

precompile(Tuple{typeof(Base.Filesystem.mkpath), String})
precompile(Tuple{typeof(QuartoNotebookWorker.refresh!), Base.Dict{String, Any}})
precompile(Tuple{typeof(QuartoNotebookWorker.refresh!), Base.Dict{String, Any}, Base.Dict{String, Any}})

module __PrecompilationModule end

QuartoNotebookWorker.NotebookState.NotebookModuleForPrecompile[] = __PrecompilationModule

PrecompileTools.@compile_workload begin
    for code in ["1 + 1", "println(\"abc\")", "error()"]
        result = QuartoNotebookWorker.render(
            code,
            "some_file",
            1,
            Dict{String,Any}("error" => "true");
            inline = false,
        )
        io = IOBuffer()
        bson = QuartoNotebookWorker.Packages.BSON.bson(io, Dict{Symbol,Any}(:data => result))
        seekstart(io)
        QuartoNotebookWorker.Packages.BSON.load(io)[:data]
    end
end

QuartoNotebookWorker.NotebookState.NotebookModuleForPrecompile[] = nothing