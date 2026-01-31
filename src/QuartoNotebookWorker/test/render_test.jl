@testitem "render_mimetypes basic" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # String output - result values are NamedTuple{(:error, :data)}
    result = QNW.render_mimetypes("hello", Dict{String,Any}())
    @test haskey(result, "text/plain")
    @test result["text/plain"].error == false
    @test String(result["text/plain"].data) == "\"hello\""

    # Number output
    result = QNW.render_mimetypes(42, Dict{String,Any}())
    @test haskey(result, "text/plain")
    @test result["text/plain"].error == false
    @test String(result["text/plain"].data) == "42"
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
