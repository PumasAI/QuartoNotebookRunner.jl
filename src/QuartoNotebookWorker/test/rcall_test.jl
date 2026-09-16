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

    QNW.NotebookState.with_test_context() do
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
end

@testitem "render() with R code boilerplate" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            RCallSetup.wrap_r("sum(1:5)"),
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

@testitem "render() inline R code" tags = [:integration, :rcall] setup = [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            RCallSetup.wrap_r("2 + 2"),
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

@testitem "render() R code error handling" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            RCallSetup.wrap_r("stop(\"intentional error\")"),
            "test.qmd",
            1,
            Dict{String,Any}();
            mod,
        )

        @test length(response.cells) == 1
        @test !isnothing(response.cells[1].error)
    end
end

@testitem "render() R plot with fig-format svg" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    options = Dict{String,Any}(
        "format" => Dict{String,Any}(
            "execute" => Dict{String,Any}(
                "fig-format" => "svg",
                "fig-width" => 6,
                "fig-height" => 5,
                "fig-dpi" => 96,
            ),
        ),
    )

    QNW.NotebookState.with_test_context(; options) do
        QNW.run_package_loading_hooks()
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            RCallSetup.wrap_r("plot(1:10)"),
            "test.qmd",
            1,
            Dict{String,Any}();
            mod,
        )

        @test isnothing(response.cells[1].error)
        display_results = response.cells[1].display_results
        @test length(display_results) == 1
        svg = String(display_results[1]["image/svg+xml"].data)
        # R's svg() sizes in inches and writes points, so 6 by 5 inches is 432 by 360.
        @test contains(svg, "width=\"432pt\"")
        @test contains(svg, "height=\"360pt\"")
    end
end

@testitem "render() R plot with fig-format png" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    import QuartoNotebookWorker as QNW
    using RCall

    Core.eval(Main, :(QuartoNotebookWorker = $QNW))

    options = Dict{String,Any}(
        "format" => Dict{String,Any}(
            "execute" => Dict{String,Any}(
                "fig-format" => "png",
                "fig-width" => 6,
                "fig-height" => 5,
                "fig-dpi" => 96,
            ),
        ),
    )

    QNW.NotebookState.with_test_context(; options) do
        QNW.run_package_loading_hooks()
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render(
            RCallSetup.wrap_r("plot(1:10)"),
            "test.qmd",
            1,
            Dict{String,Any}();
            mod,
        )

        @test isnothing(response.cells[1].error)
        display_results = response.cells[1].display_results
        @test length(display_results) == 1
        png = display_results[1]["image/png"].data
        # R's png() sizes in pixels, so 6 by 5 inches at 96 dpi is 576 by 480.
        big_endian(bytes) = reduce((acc, b) -> acc * 256 + b, bytes; init = 0)
        @test big_endian(png[17:20]) == 576
        @test big_endian(png[21:24]) == 480
    end
end

@testitem "RCall evaluates R code" tags = [:integration, :rcall] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.with_test_context() do
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
end
