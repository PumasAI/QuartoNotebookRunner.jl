@testitem "LaTeXStrings renders markdown" begin
    import QuartoNotebookWorker as QNW
    import LaTeXStrings: @L_str

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        s = L"x^2 + y^2"
        result = QNW.render_mimetypes(s, mod, Dict{String,Any}())

        @test haskey(result, "text/markdown")
        md = String(result["text/markdown"].data)
        @test startswith(md, "\$")
        @test endswith(rstrip(md), "\$")
    end
end

@testitem "LaTeXStrings typst wrapping" begin
    import QuartoNotebookWorker as QNW
    import LaTeXStrings: LaTeXString

    options = Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => "typst")))
    QNW.NotebookState.with_test_context(; options) do
        mod = QNW.NotebookState.notebook_module()

        # String without leading $ gets wrapped in $$ for typst
        s = LaTeXString("x^2")
        result = QNW.render_mimetypes(s, mod, Dict{String,Any}())

        @test haskey(result, "text/markdown")
        md = String(result["text/markdown"].data)
        @test startswith(md, "\$\$")
        @test endswith(rstrip(md), "\$\$")
    end
end
