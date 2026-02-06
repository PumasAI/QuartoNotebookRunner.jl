@testmodule PythonCallSetup begin
    using PythonCall

    # Exact pattern from wrap_with_python_boilerplate in cell_processing.jl
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

    using PythonCall

    QNW.NotebookState.with_test_context() do
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
end

@testitem "render() with Python code boilerplate" tags = [:integration] setup =
    [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    # Bind QuartoNotebookWorker in Main so Main.QuartoNotebookWorker.py"..." works
    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            PythonCallSetup.wrap_python("sum([1, 2, 3, 4, 5])"),
            "test.qmd",
            1,
            Dict{String,Any}();
            mod,
        )

        @test !response.is_expansion
        @test length(response.cells) == 1
        @test isnothing(response.cells[1].error)
        @test haskey(response.cells[1].results, "text/plain")
        @test contains(String(response.cells[1].results["text/plain"].data), "15")
    end
end

@testitem "render() inline Python code" tags = [:integration] setup = [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            PythonCallSetup.wrap_python("2 + 2"),
            "test.qmd",
            1,
            Dict{String,Any}();
            inline = true,
            mod,
        )

        @test length(response.cells) == 1
        @test isnothing(response.cells[1].error)
        @test contains(String(response.cells[1].results["text/plain"].data), "4")
    end
end

@testitem "render() Python code error handling" tags = [:integration] setup =
    [PythonCallSetup] begin
    import QuartoNotebookWorker as QNW
    using PythonCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            PythonCallSetup.wrap_python("raise ValueError(\"intentional error\")"),
            "test.qmd",
            1,
            Dict{String,Any}();
            mod,
        )

        @test length(response.cells) == 1
        @test !isnothing(response.cells[1].error)
    end
end
