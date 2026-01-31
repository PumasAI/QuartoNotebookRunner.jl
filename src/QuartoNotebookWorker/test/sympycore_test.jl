@testitem "SymPyCore renders as markdown" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using SymPyPythonCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    @syms x
    expr = sin(x)^2 / 2

    result = QNW.render_mimetypes(expr, Dict{String,Any}())

    @test haskey(result, "text/markdown")
    md = String(result["text/markdown"].data)
    @test contains(md, "sin") || contains(md, "\\sin")
end
