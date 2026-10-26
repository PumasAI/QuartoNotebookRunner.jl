@testitem "streams keep the order the cell wrote them in" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        println(stderr, "two")
        println("three")
        println("four")
        """
        response = QNW.render(code, "test.jl", 1; mod)
        @test response.cells[1].streams ==
              [("stdout", "one\n"), ("stderr", "two\n"), ("stdout", "three\nfour\n")]
    end
end

@testitem "log records go to stderr" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("@warn \"careful\"", "test.jl", 1; mod)
        name, text = only(response.cells[1].streams)
        @test name == "stderr"
        @test contains(text, "Warning:")
        @test contains(text, "careful")
    end
end

@testitem "subprocess output keeps its stream" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        script = "println(\\"out\\"); println(stderr, \\"err\\")"
        run(`\$(Base.julia_cmd()) --startup-file=no -e \$script`)
        nothing
        """
        response = QNW.render(code, "test.jl", 1; mod)
        streams = Dict(response.cells[1].streams)
        @test streams["stdout"] == "out\n"
        @test streams["stderr"] == "err\n"
    end
end

@testitem "warning false drops stderr and joins the stdout around it" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        @warn "hidden warning"
        @error "hidden error"
        println(stderr, "hidden direct write")
        println("two")
        """
        options = Dict{String,Any}("warning" => false)
        response = QNW.render(code, "test.jl", 1, options; mod)
        @test response.cells[1].streams == [("stdout", "one\ntwo\n")]
    end
end

@testitem "warning false still delivers records to the cell's own logger" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        buffer = IOBuffer()
        Base.CoreLogging.with_logger(Base.CoreLogging.SimpleLogger(buffer)) do
            @warn "kept"
        end
        contains(String(take!(buffer)), "kept")
        """
        options = Dict{String,Any}("warning" => false)
        response = QNW.render(code, "test.jl", 1, options; mod)
        @test String(response.cells[1].results["text/plain"].data) == "true"
    end
end

@testitem "a finished cell's streams write to the current cell" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        saved = stdout
        logger = Base.CoreLogging.SimpleLogger(stderr)
        nothing
        """
        QNW.render(code, "test.jl", 1; mod)
        code = """
        println(saved, "late")
        Base.CoreLogging.with_logger(() -> @warn("late warning"), logger)
        """
        response = QNW.render(code, "test.jl", 2; mod)
        @test response.cells[1].error === nothing
        @test first.(response.cells[1].streams) == ["stdout", "stderr"]
        @test last(response.cells[1].streams[1]) == "late\n"
        @test contains(last(response.cells[1].streams[2]), "late warning")
    end
end

@testitem "a cell that writes nothing has no streams" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("1 + 1", "test.jl", 1; mod)
        @test isempty(response.cells[1].streams)
    end
end
