@testitem "SymPyCore renders as markdown" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using SymPyPythonCall

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        @syms x
        expr = sin(x)^2 / 2

        result = QNW.render_mimetypes(expr, mod, Dict{String,Any}())

        @test haskey(result, "text/markdown")
        md = String(result["text/markdown"].data)
        @test contains(md, "sin") || contains(md, "\\sin")
    end
end
