@testmodule PythonCallSetup begin
    using PythonCall

    # Exact pattern from wrap_with_python_boilerplate in server.jl
    function wrap_python(code)
        """
        Main.QuartoNotebookWorker.py\"\"\"
        $code
        \"\"\"
        """
    end
end

@testitem "PythonCall evaluates Python code" tags = [:integration] begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    using PythonCall

    nb_mod = QNW.NotebookState.notebook_module()

    # Test basic Python evaluation
    result = QNW._py_expr(nothing, "1 + 2", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test pyconvert(Int, value) == 3

    # Test Python None returns Julia nothing
    result = QNW._py_expr(nothing, "None", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test isnothing(value)
end

@testitem "render() with Python code boilerplate" tags = [:integration] setup =
    [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    # Bind QuartoNotebookWorker in Main so Main.QuartoNotebookWorker.py"..." works
    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    results, is_expansion = QNW.render(
        PythonCallSetup.wrap_python("sum([1, 2, 3, 4, 5])"),
        "test.qmd",
        1,
        Dict{String,Any}(),
    )

    @test !is_expansion
    @test length(results) == 1
    @test isnothing(results[1].error)
    @test haskey(results[1].results, "text/plain")
    @test contains(String(results[1].results["text/plain"].data), "15")
end

@testitem "render() inline Python code" tags = [:integration] setup = [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    results, _ = QNW.render(
        PythonCallSetup.wrap_python("2 + 2"),
        "test.qmd",
        1,
        Dict{String,Any}();
        inline = true,
    )

    @test length(results) == 1
    @test isnothing(results[1].error)
    @test contains(String(results[1].results["text/plain"].data), "4")
end

@testitem "render() Python code error handling" tags = [:integration] setup =
    [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    results, _ = QNW.render(
        PythonCallSetup.wrap_python("raise ValueError(\"intentional error\")"),
        "test.qmd",
        1,
        Dict{String,Any}(),
    )

    @test length(results) == 1
    @test !isnothing(results[1].error)
end
