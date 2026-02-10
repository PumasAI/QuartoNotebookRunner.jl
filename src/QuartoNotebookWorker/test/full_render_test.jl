@testitem "render basic code" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        # Basic expression
        response = QNW.render("1 + 1", "test.jl", 1; mod)
        @test response.is_expansion == false
        @test length(response.cells) == 1
        @test response.cells[1].error === nothing
        @test haskey(response.cells[1].results, "text/plain")
        @test String(response.cells[1].results["text/plain"].data) == "2"
    end
end

@testitem "render with output" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("println(\"hello\")", "test.jl", 1; mod)
        @test response.cells[1].output == "hello\n"
    end
end

@testitem "render with semicolon suppresses output" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("x = 42;", "test.jl", 1; mod)
        @test isempty(response.cells[1].results)
    end
end

@testitem "render error" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("error(\"test error\")", "test.jl", 1; mod)
        @test response.cells[1].error == "ErrorException"
        @test !isempty(response.cells[1].backtrace)
    end
end

@testitem "render parse error" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("1 +", "test.jl", 1; mod)
        # Julia 1.6 throws ErrorException, later versions throw ParseError
        @test response.cells[1].error in ("Base.Meta.ParseError", "ErrorException")
    end
end

@testitem "render with cell expansion" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        nb_mod = QNW.NotebookState.notebook_module()

        # Define expandable type and expand method via render
        setup_code = """
        import QuartoNotebookWorker
        struct Expandable
            values::Vector{Int}
        end
        QuartoNotebookWorker.expand(e::Expandable) = [QuartoNotebookWorker.Cell(v) for v in e.values]
        """
        QNW.render(setup_code, "test.jl", 1; mod = nb_mod)

        response = QNW.render("Expandable([1, 2, 3])", "test.jl", 1; mod = nb_mod)
        @test response.is_expansion == true
        @test length(response.cells) == 3
    end
end

@testitem "render inline mode" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("\"hello\"", "test.jl", 1; inline = true, mod)
        # inline mode uses print not show, so no quotes
        @test String(response.cells[1].results["text/plain"].data) == "hello"
    end
end

@testitem "PNG show method" begin
    import QuartoNotebookWorker as QNW

    png_bytes = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    png = QNW.PNG(png_bytes)

    buf = IOBuffer()
    show(buf, MIME"image/png"(), png)
    @test take!(buf) == png_bytes
end

@testitem "SVG show method randomizes IDs" begin
    import QuartoNotebookWorker as QNW

    svg_content = """<svg><defs><path id="glyph0"/></defs><use href="#glyph0"/></svg>"""
    svg = QNW.SVG(Vector{UInt8}(svg_content))

    buf = IOBuffer()
    show(buf, MIME"image/svg+xml"(), svg)
    result = String(take!(buf))

    # IDs should be randomized (not match original)
    @test !contains(result, "id=\"glyph0\"")
    @test !contains(result, "href=\"#glyph0\"")
    # But structure preserved
    @test contains(result, "id=\"glyph")
    @test contains(result, "href=\"#glyph")
end

@testitem "clean_bt_str returns empty for non-error" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestMod)
    result = QNW.clean_bt_str(false, [], nothing, mod)
    @test result == UInt8[]
end

@testitem "ojs_define generates HTML" begin
    import QuartoNotebookWorker as QNW
    using JSON3

    QNW.NotebookState.with_test_context() do
        html = QNW.ojs_define(x = 1, y = "test")
        buf = IOBuffer()
        show(buf, MIME"text/html"(), html)
        result = String(take!(buf))

        @test contains(result, "<script type='ojs-define'>")
        @test contains(result, "contents")
    end
end

@testitem "render with warning=false suppresses logging" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        # warning=false should suppress warnings during render
        cell_options = Dict{String,Any}("warning" => false)
        response = QNW.render("@warn \"test warning\"; 42", "test.jl", 1, cell_options; mod)
        @test response.cells[1].error === nothing
        @test String(response.cells[1].results["text/plain"].data) == "42"
    end
end

@testitem "clean_bt_str with mimetype=true" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestMod)

    # Create a fake error with backtrace
    bt = try
        error("test")
    catch
        catch_backtrace()
    end
    err = ErrorException("test")

    result = QNW.clean_bt_str(true, bt, err, mod, "", true)
    @test result isa Vector{UInt8}
    @test length(result) > 0
end

@testitem "render_mimetypes catches show errors" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        # Define a type that errors on show via render
        setup_code = """
        struct BrokenShow end
        Base.show(io::IO, ::MIME"text/plain", ::BrokenShow) = error("show failed")
        BrokenShow()
        """
        response = QNW.render(setup_code, "test.jl", 1; mod)
        @test haskey(response.cells[1].results, "text/plain")
        @test response.cells[1].results["text/plain"].error == true
        @test contains(String(response.cells[1].results["text/plain"].data), "show failed")
    end
end
