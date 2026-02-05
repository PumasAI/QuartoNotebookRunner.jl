@testitem "render_mimetypes basic" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        # String output - result values are MimeResult(mime, error, data)
        result = QNW.render_mimetypes("hello", mod, Dict{String,Any}())
        @test haskey(result, "text/plain")
        @test result["text/plain"].error == false
        @test String(result["text/plain"].data) == "\"hello\""

        # Number output
        result = QNW.render_mimetypes(42, mod, Dict{String,Any}())
        @test haskey(result, "text/plain")
        @test result["text/plain"].error == false
        @test String(result["text/plain"].data) == "42"
    end
end

@testitem "_process_code help mode" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestModHelp)
    expr = QNW._process_code(mod, "?sum"; filename = "test.qmd", lineno = 1)
    @test Meta.isexpr(expr, :toplevel)
    str = string(expr)
    @test contains(str, "helpmode") || contains(str, "doc")
end

@testitem "_process_code shell mode" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestModShell)
    expr = QNW._process_code(mod, ";echo hello"; filename = "test.qmd", lineno = 1)
    @test Meta.isexpr(expr, :toplevel)
    str = string(expr)
    @test contains(str, "run")
    @test contains(str, "echo hello")
end

@testitem "_process_code pkg mode" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestModPkg)
    expr = QNW._process_code(mod, "]status"; filename = "test.qmd", lineno = 1)
    @test Meta.isexpr(expr, :toplevel)
    str = string(expr)
    @test contains(str, "Pkg") || contains(str, "REPLMode")
    @test contains(str, "status")
end

@testitem "_process_code normal" begin
    import QuartoNotebookWorker as QNW

    mod = Module(:TestModNormal)
    expr = QNW._process_code(mod, "x = 1\ny = 2"; filename = "test.qmd", lineno = 1)
    @test Meta.isexpr(expr, :toplevel)
    @test length(expr.args) >= 2
end

@testitem "_transform_output" begin
    import QuartoNotebookWorker as QNW

    # Normal MIME - passes through
    buf = IOBuffer("hello")
    skip, mime, out = QNW._transform_output("text/plain", buf)
    @test skip == false
    @test mime == "text/plain"

    # openxml MIME - wraps in raw block
    buf = IOBuffer("<w:p>content</w:p>")
    skip, mime, out = QNW._transform_output("QuartoNotebookRunner/openxml", buf)
    @test skip == true
    @test mime == "text/markdown"
    @test contains(String(take!(out)), "```{=openxml}")

    # typst MIME - wraps in raw block
    buf = IOBuffer("#table()")
    skip, mime, out = QNW._transform_output("QuartoNotebookRunner/typst", buf)
    @test skip == true
    @test mime == "text/markdown"
    @test contains(String(take!(out)), "```{=typst}")
end

@testitem "render with custom typst MIME" begin
    import QuartoNotebookWorker as QNW

    options = Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => "typst")))
    QNW.NotebookState.with_test_context(; options) do
        nb_mod = QNW.NotebookState.notebook_module()
        Core.eval(
            nb_mod,
            quote
                struct TypstTable end
                Base.show(io::IO, ::MIME"QuartoNotebookRunner/typst", ::TypstTable) =
                    print(io, "#table()")
            end,
        )

        response = QNW.render("TypstTable()", "test.jl", 1; mod = nb_mod)

        @test length(response.cells) == 1
        @test haskey(response.cells[1].results, "text/markdown")
        md = String(response.cells[1].results["text/markdown"].data)
        @test contains(md, "```{=typst}")
        @test contains(md, "#table()")
    end
end

@testitem "soft scope" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        s = 0
        for i = 1:10
            s += i
        end
        s
        """
        response = QNW.render(code, "test.jl", 1; mod)
        @test String(response.cells[1].results["text/plain"].data) == "55"
    end
end

@testitem "shell mode execution" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        if !Sys.iswindows()
            response = QNW.render(";echo OK", "test.jl", 1; mod)
            @test contains(response.cells[1].output, "OK")
        else
            response = QNW.render(";cmd /c echo OK", "test.jl", 1; mod)
            @test contains(response.cells[1].output, "OK")
        end
    end
end

@testitem "pkg mode execution" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("]status", "test.jl", 1; mod)
        @test contains(response.cells[1].output, "Status") ||
              contains(response.cells[1].output, "Project")
    end
end

@testitem "help mode execution" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("?Int64", "test.jl", 1; mod)
        @test haskey(response.cells[1].results, "text/plain")
        @test contains(
            String(response.cells[1].results["text/plain"].data),
            "64-bit signed integer",
        )
    end
end

@testitem "print custom struct" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        struct M
            a::Int
        end
        x = M(22)
        print(x)
        """
        response = QNW.render(code, "test.jl", 1; mod)
        @test response.cells[1].output == "M(22)"
    end
end

@testitem "display with specific MIME" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response =
            QNW.render("display(MIME(\"text/html\"), HTML(\"<p></p>\"))", "test.jl", 1; mod)
        @test length(response.cells[1].display_results) == 1
        @test haskey(response.cells[1].display_results[1], "text/html")
        @test String(response.cells[1].display_results[1]["text/html"].data) == "<p></p>"
    end
end
