@testmodule RCallSetup begin
    using RCall

    # Exact pattern from wrap_with_r_boilerplate in cell_processing.jl
    function wrap_r(code)
        """
        Main.QuartoNotebookWorker.R\"\"\"
        $code
        \"\"\"
        """
    end
end

@testitem "RCall extension hooks" tags = [:integration, :rcall] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Test R evaluation works
    result = RCall.rcopy(Int, RCall.reval("1 + 2"))
    @test result == 3

    # Test refresh clears R workspace
    RCall.reval("test_var <- 42")
    @test RCall.rcopy(Int, RCall.reval("test_var")) == 42

    # Refresh hooks clear R workspace
    QNW.run_package_refresh_hooks()
    @test_throws RCall.REvalError RCall.reval("test_var")
end

@testitem "render() with R code boilerplate" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    response = QNW.render(RCallSetup.wrap_r("sum(1:5)"), "test.qmd", 1, Dict{String,Any}())

    @test !response.is_expansion
    @test length(response.cells) == 1
    @test isnothing(response.cells[1].error)
    @test haskey(response.cells[1].results, "text/plain")
    @test contains(String(response.cells[1].results["text/plain"].data), "15")
end

@testitem "render() inline R code" tags = [:integration, :rcall] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    response = QNW.render(
        RCallSetup.wrap_r("2 + 2"),
        "test.qmd",
        1,
        Dict{String,Any}();
        inline = true,
    )

    @test length(response.cells) == 1
    @test isnothing(response.cells[1].error)
    @test contains(String(response.cells[1].results["text/plain"].data), "4")
end

@testitem "render() R code error handling" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    response = QNW.render(
        RCallSetup.wrap_r("stop(\"intentional error\")"),
        "test.qmd",
        1,
        Dict{String,Any}(),
    )

    @test length(response.cells) == 1
    @test !isnothing(response.cells[1].error)
end

@testitem "RCall evaluates R code" tags = [:integration, :rcall] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    nb_mod = QNW.NotebookState.notebook_module()

    # Test basic R evaluation
    result = QNW._r_expr(nothing, "1 + 2", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test value == 3

    # Test R NULL returns Julia nothing
    result = QNW._r_expr(nothing, "NULL", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test isnothing(value)
end
