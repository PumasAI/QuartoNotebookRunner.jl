@testitem "ManifestInSyncRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.ManifestInSyncRequest()
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.ManifestInSyncRequest
end

@testitem "NotebookInitRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.NotebookInitRequest(
        file = "/path/to/notebook.qmd",
        project = "/path/to/project",
        options = Dict{String,Any}("foo" => 1, "bar" => "baz"),
        cwd = "/path/to",
        env_vars = ["VAR1=value1", "VAR2=value2"],
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.NotebookInitRequest
    @test result.file == req.file
    @test result.project == req.project
    @test result.options == req.options
    @test result.cwd == req.cwd
    @test result.env_vars == req.env_vars
end

@testitem "NotebookCloseRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.NotebookCloseRequest(file = "/path/to/notebook.qmd")
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.NotebookCloseRequest
    @test result.file == req.file
end

@testitem "RenderRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.RenderRequest(
        code = "1 + 1",
        file = "test.qmd",
        notebook = "/path/to/notebook.qmd",
        line = 42,
        cell_options = Dict{String,Any}("echo" => false),
        inline = true,
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.RenderRequest
    @test result.code == req.code
    @test result.file == req.file
    @test result.notebook == req.notebook
    @test result.line == req.line
    @test result.cell_options == req.cell_options
    @test result.inline == req.inline
end

@testitem "EvaluateParamsRequest roundtrip" begin
    import QuartoNotebookWorker as QNW
    IPC = QNW.WorkerIPC

    req = IPC.EvaluateParamsRequest(
        file = "/path/to/notebook.qmd",
        params = Dict{String,Any}("x" => 1, "y" => "str", "z" => [1.0, 2.0]),
    )
    bytes = IPC._ipc_serialize(req)
    result = IPC._ipc_deserialize(bytes)

    @test result isa IPC.EvaluateParamsRequest
    @test result.file == req.file
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
