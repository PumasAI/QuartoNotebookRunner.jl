@testitem "Tables.jl OJS conversion" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using DataFrames

    QNW.NotebookState.with_test_context() do
        df = DataFrame(a = [1, 2], b = ["x", "y"])

        @test QNW._istable(df) == true
        rows = QNW._ojs_rows(df)
        @test rows == [(a = 1, b = "x"), (a = 2, b = "y")]
    end
end

@testitem "DataFrames produces text/html" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using DataFrames

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        df = DataFrame(a = [1, 2], b = ["x", "y"])
        result = QNW.render_mimetypes(df, mod, Dict{String,Any}())

        @test haskey(result, "text/plain")
        @test haskey(result, "text/html")
        @test contains(String(result["text/html"].data), "<table")
    end
end
