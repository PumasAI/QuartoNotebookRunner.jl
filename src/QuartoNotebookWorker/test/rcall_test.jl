@testmodule RCallSetup begin
    import QuartoNotebookWorker as QNW
    using RCall

    # Exact pattern from wrap_with_r_boilerplate in cell_processing.jl
    function wrap_r(code)
        """
        Main.QuartoNotebookWorker.R\"\"\"
        $code
        \"\"\"
        """
    end

    # `cell.error` carries only the exception name, so pull the message out of
    # the backtrace to give a failing assertion something to show.
    cell_error(cell) =
        cell.error === nothing ? nothing : join([cell.error; cell.backtrace], "\n")

    const SVG_DEVICE_PROBE = """
    tryCatch({
        file <- tempfile(fileext = ".svg")
        svg(file)
        dev.off()
        unlink(file)
        TRUE
    }, error = function(e) FALSE)
    """

    # R's svg() needs cairo, which the macOS build loads from XQuartz. The
    # capability flag still reads true when that library is missing, so ask for
    # a device rather than trusting it.
    svg_device_available() = RCall.rcopy(Bool, RCall.reval(SVG_DEVICE_PROBE))

    function render_plot(fig_format, code = "plot(1:10)")
        Core.eval(Main, :(QuartoNotebookWorker = $QNW))
        options = Dict{String,Any}(
            "format" => Dict{String,Any}(
                "execute" => Dict{String,Any}(
                    "fig-format" => fig_format,
                    "fig-width" => 6,
                    "fig-height" => 5,
                    "fig-dpi" => 96,
                ),
            ),
        )
        return QNW.NotebookState.with_test_context(; options) do
            QNW.run_package_loading_hooks()
            mod = QNW.NotebookState.notebook_module()
            QNW.render(wrap_r(code), "test.qmd", 1, Dict{String,Any}(); mod)
        end
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
    if !RCallSetup.svg_device_available()
        @info "skipping svg figure test, this R cannot open an svg device"
    else
        response = RCallSetup.render_plot("svg")

        @test RCallSetup.cell_error(response.cells[1]) === nothing
        display_results = response.cells[1].display_results
        @test length(display_results) == 1
        svg = String(display_results[1]["image/svg+xml"].data)
        # Cairo builds disagree on whether the header carries a `pt` suffix, so
        # read the numbers out instead of matching the attribute text.
        header = match(r"<svg\b[^>]*>", svg).match
        function dimension(name)
            m = match(Regex("\\b$(name)=\"([0-9.]+)(?:pt)?\""), header)
            m === nothing && error("no $name attribute in $header")
            return parse(Float64, m[1])
        end
        # R's svg() sizes in inches and writes points, so 6 by 5 inches is 432 by
        # 360. Handing it pixels instead would give 41472 by 34560.
        @test dimension("width") == 432
        @test dimension("height") == 360
    end
end

@testitem "render() R plot with fig-format png" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    response = RCallSetup.render_plot("png")

    @test RCallSetup.cell_error(response.cells[1]) === nothing
    display_results = response.cells[1].display_results
    @test length(display_results) == 1
    png = display_results[1]["image/png"].data
    # R's png() sizes in pixels, so 6 by 5 inches at 96 dpi is 576 by 480.
    big_endian(bytes) = reduce((acc, b) -> acc * 256 + b, bytes; init = 0)
    @test big_endian(png[17:20]) == 576
    @test big_endian(png[21:24]) == 480
end

@testitem "render() R png device honours fig-dpi" tags = [:integration, :rcall] setup =
    [RCallSetup] begin
    response = RCallSetup.render_plot(
        "png",
        """
        plot(1:10)
        sprintf("%.2f by %.2f inches", dev.size("in")[1], dev.size("in")[2])
        """,
    )

    @test RCallSetup.cell_error(response.cells[1]) === nothing
    # `res` turns the pixel size back into inches. Without it R falls back to 72
    # dpi and those 576 by 480 pixels become an 8 by 6.67 inch figure.
    text = String(response.cells[1].results["text/plain"].data)
    @test contains(text, "6.00 by 5.00 inches")
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
