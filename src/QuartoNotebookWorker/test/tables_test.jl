@testitem "Tables.jl OJS conversion" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using DataFrames

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    df = DataFrame(a = [1, 2], b = ["x", "y"])

    @test QNW._istable(df) == true
    rows = QNW._ojs_rows(df)
    @test rows == [(a = 1, b = "x"), (a = 2, b = "y")]
end
