@testmodule RCallSetup begin
    using RCall

    # Exact pattern from wrap_with_r_boilerplate in server.jl
    function wrap_r(code)
        """
        @isdefined(RCall) && RCall isa Module && Base.PkgId(RCall).uuid == Base.UUID("6f49c342-dc21-5d91-9882-a32aef131414") || error("RCall must be imported to execute R code cells with QuartoNotebookRunner")
        RCall.rcopy(RCall.R\"\"\"
        $code
        \"\"\")
        """
    end
end

@testitem "RCall extension hooks" tags = [:integration] begin
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

@testitem "render() with R code boilerplate" tags = [:integration] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    Core.eval(QNW.NotebookState.notebook_module(), :(using RCall))

    response = QNW.render(RCallSetup.wrap_r("sum(1:5)"), "test.qmd", 1, Dict{String,Any}())

    @test !response.is_expansion
    @test length(response.cells) == 1
    @test isnothing(response.cells[1].error)
    @test haskey(response.cells[1].results, "text/plain")
    @test contains(String(response.cells[1].results["text/plain"].data), "15")
end

@testitem "render() inline R code" tags = [:integration] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    Core.eval(QNW.NotebookState.notebook_module(), :(using RCall))

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

@testitem "render() R code error handling" tags = [:integration] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    Core.eval(QNW.NotebookState.notebook_module(), :(using RCall))

    response = QNW.render(
        RCallSetup.wrap_r("stop(\"intentional error\")"),
        "test.qmd",
        1,
        Dict{String,Any}(),
    )

    @test length(response.cells) == 1
    @test !isnothing(response.cells[1].error)
end

@testitem "render() R without RCall imported" tags = [:integration] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    response = QNW.render(RCallSetup.wrap_r("1 + 1"), "test.qmd", 1, Dict{String,Any}())

    @test length(response.cells) == 1
    @test !isnothing(response.cells[1].error)
    @test contains(join(response.cells[1].backtrace, "\n"), "RCall must be imported")
end
