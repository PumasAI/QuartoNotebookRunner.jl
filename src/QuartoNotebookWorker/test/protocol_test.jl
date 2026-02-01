@testitem "ManifestInSyncRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.ManifestInSyncRequest()
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.ManifestInSyncRequest
end

@testitem "WorkerInitRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.WorkerInitRequest(
        path = "/path/to/notebook.qmd",
        options = Dict{String,Any}("foo" => 1, "bar" => "baz"),
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.WorkerInitRequest
    @test result.path == req.path
    @test result.options == req.options
end

@testitem "WorkerRefreshRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.WorkerRefreshRequest(options = Dict{String,Any}("key" => [1, 2, 3]))
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.WorkerRefreshRequest
    @test result.options == req.options
end

@testitem "SetEnvVarsRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.SetEnvVarsRequest(vars = ["VAR1=value1", "VAR2=value2"])
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.SetEnvVarsRequest
    @test result.vars == req.vars
end

@testitem "RenderRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.RenderRequest(
        code = "1 + 1",
        file = "test.qmd",
        line = 42,
        cell_options = Dict{String,Any}("echo" => false),
        inline = true,
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.RenderRequest
    @test result.code == req.code
    @test result.file == req.file
    @test result.line == req.line
    @test result.cell_options == req.cell_options
    @test result.inline == req.inline
end

@testitem "EvaluateParamsRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.EvaluateParamsRequest(
        params = Dict{String,Any}("x" => 1, "y" => "str", "z" => [1.0, 2.0]),
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.EvaluateParamsRequest
    @test result.params == req.params
end

@testitem "RenderResponse roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    cell = IPC.CellResult(
        "code",
        Dict{String,Any}("opt" => true),
        Dict{String,IPC.MimeResult}(
            "text/plain" => IPC.MimeResult("text/plain", false, UInt8[0x32]),
        ),
        [
            Dict{String,IPC.MimeResult}(
                "text/html" =>
                    IPC.MimeResult("text/html", false, UInt8[0x3c, 0x70, 0x3e]),
            ),
        ],
        "output\n",
        nothing,
        String[],
    )
    resp = IPC.RenderResponse([cell], false)
    bytes = IPC._ipc_serialize(resp)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.RenderResponse
    @test length(result.cells) == 1
    @test result.is_expansion == false
    @test result.cells[1].code == "code"
    @test result.cells[1].output == "output\n"
    @test result.cells[1].error === nothing
    @test haskey(result.cells[1].results, "text/plain")
    @test result.cells[1].results["text/plain"].data == UInt8[0x32]
end
