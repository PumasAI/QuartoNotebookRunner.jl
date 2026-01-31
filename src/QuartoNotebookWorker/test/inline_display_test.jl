@testitem "with_inline_display captures display calls" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    cell_opts = Dict{String,Any}()
    result, queue = QNW.with_inline_display(cell_opts) do
        display("first")
        display(42)
        :return_value
    end

    @test result == :return_value
    @test length(queue) == 2
    # Queue items are rendered mimetype dicts
    @test queue[1] isa Dict
    @test haskey(queue[1], "text/plain")
    @test queue[2] isa Dict
    @test haskey(queue[2], "text/plain")
end
