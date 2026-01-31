@testitem "RemoteREPL extension loads" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using RemoteREPL

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Extension should load without error
    @test true
end
