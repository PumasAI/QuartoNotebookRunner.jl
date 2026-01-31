@testitem "render basic code" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Basic expression
    result, is_expansion = QNW.render("1 + 1", "test.jl", 1)
    @test is_expansion == false
    @test length(result) == 1
    @test result[1].error === nothing
    @test haskey(result[1].results, "text/plain")
    @test String(result[1].results["text/plain"].data) == "2"
end

@testitem "render with output" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result, _ = QNW.render("println(\"hello\")", "test.jl", 1)
    @test result[1].output == "hello\n"
end

@testitem "render with semicolon suppresses output" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result, _ = QNW.render("x = 42;", "test.jl", 1)
    @test isempty(result[1].results)
end

@testitem "render error" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result, _ = QNW.render("error(\"test error\")", "test.jl", 1)
    @test result[1].error == "ErrorException"
    @test !isempty(result[1].backtrace)
end

@testitem "render parse error" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result, _ = QNW.render("1 +", "test.jl", 1)
    @test result[1].error == "Base.Meta.ParseError"
end

@testitem "render with cell expansion" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Define expandable type in notebook module
    nb_mod = QNW.NotebookState.notebook_module()
    Core.eval(nb_mod, quote
        struct Expandable
            values::Vector{Int}
        end
    end)
    Core.eval(
        Main,
        quote
            import QuartoNotebookWorker as QNW
            QNW.expand(e::Main.Notebook.Expandable) = [QNW.Cell(v) for v in e.values]
        end,
    )

    result, is_expansion = QNW.render("Expandable([1, 2, 3])", "test.jl", 1)
    @test is_expansion == true
    @test length(result) == 3
end

@testitem "render inline mode" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result, _ = QNW.render("\"hello\"", "test.jl", 1; inline = true)
    # inline mode uses print not show, so no quotes
    @test String(result[1].results["text/plain"].data) == "hello"
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

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    result = QNW.clean_bt_str(false, [], nothing)
    @test result == UInt8[]
end

@testitem "ojs_define generates HTML" begin
    import QuartoNotebookWorker as QNW
    using JSON3

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    html = QNW.ojs_define(x = 1, y = "test")
    buf = IOBuffer()
    show(buf, MIME"text/html"(), html)
    result = String(take!(buf))

    @test contains(result, "<script type='ojs-define'>")
    @test contains(result, "contents")
end

@testitem "render with warning=false suppresses logging" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # warning=false should suppress warnings during render
    cell_options = Dict{String,Any}("warning" => false)
    result, _ = QNW.render("@warn \"test warning\"; 42", "test.jl", 1, cell_options)
    @test result[1].error === nothing
    @test String(result[1].results["text/plain"].data) == "42"
end

@testitem "clean_bt_str with mimetype=true" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Create a fake error with backtrace
    bt = try
        error("test")
    catch
        catch_backtrace()
    end
    err = ErrorException("test")

    result = QNW.clean_bt_str(true, bt, err, "", true)
    @test result isa Vector{UInt8}
    @test length(result) > 0
end

@testitem "render_mimetypes catches show errors" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Define a type that errors on show
    struct BrokenShow end
    Base.show(io::IO, ::MIME"text/plain", ::BrokenShow) = error("show failed")

    result = QNW.render_mimetypes(BrokenShow(), Dict{String,Any}())
    @test haskey(result, "text/plain")
    @test result["text/plain"].error == true
    @test contains(String(result["text/plain"].data), "show failed")
end
