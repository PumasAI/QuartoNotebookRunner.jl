PrecompileTools.@setup_workload begin
    notebook = joinpath(@__DIR__, "..", "test", "examples", "cell_types.qmd")
    script = joinpath(@__DIR__, "..", "test", "examples", "cell_types.jl")
    results = Dict{String,WorkerIPC.MimeResult}()
    PrecompileTools.@compile_workload begin
        raw_text_chunks(notebook)
        raw_text_chunks(script)
        process_results(results)

        # Exercise host-side binary IPC serialization round-trips.
        for req in [
            WorkerIPC.ManifestInSyncRequest(),
            WorkerIPC.RenderRequest(;
                code = "1",
                file = "f.qmd",
                notebook = "f.qmd",
                line = 1,
                cell_options = Dict{String,Any}(),
            ),
            WorkerIPC.NotebookInitRequest(;
                file = "f.qmd",
                project = ".",
                options = Dict{String,Any}(),
                cwd = ".",
                env_vars = String[],
            ),
            WorkerIPC.NotebookCloseRequest(; file = "f.qmd"),
            WorkerIPC.EvaluateParamsRequest(;
                file = "f.qmd",
                params = Dict{String,Any}("x" => 1),
            ),
        ]
            bytes = WorkerIPC._ipc_serialize(req)
            WorkerIPC._ipc_deserialize(bytes)
        end

        # Exercise response deserialization.
        resp = WorkerIPC.RenderResponse(
            [
                WorkerIPC.CellResult(
                    "1",
                    Dict{String,Any}(),
                    Dict{String,WorkerIPC.MimeResult}(
                        "text/plain" =>
                            WorkerIPC.MimeResult("text/plain", false, UInt8[0x31]),
                    ),
                    WorkerIPC.MimeResult[],
                    "",
                    nothing,
                    String[],
                ),
            ],
            false,
        )
        bytes = WorkerIPC._ipc_serialize(resp)
        WorkerIPC._ipc_deserialize(bytes)

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
