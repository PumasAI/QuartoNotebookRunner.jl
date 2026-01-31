@testitem "LaTeXStrings renders markdown" begin
    import QuartoNotebookWorker as QNW
    import LaTeXStrings: @L_str

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    s = L"x^2 + y^2"
    result = QNW.render_mimetypes(s, Dict{String,Any}())

    @test haskey(result, "text/markdown")
    md = String(result["text/markdown"].data)
    @test startswith(md, "\$")
    @test endswith(rstrip(md), "\$")
end

@testitem "LaTeXStrings typst wrapping" begin
    import QuartoNotebookWorker as QNW
    import LaTeXStrings: LaTeXString

    QNW.NotebookState.OPTIONS[] =
        Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => "typst")))
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # String without leading $ gets wrapped in $$ for typst
    s = LaTeXString("x^2")
    result = QNW.render_mimetypes(s, Dict{String,Any}())

    @test haskey(result, "text/markdown")
    md = String(result["text/markdown"].data)
    @test startswith(md, "\$\$")
    @test endswith(rstrip(md), "\$\$")
end
