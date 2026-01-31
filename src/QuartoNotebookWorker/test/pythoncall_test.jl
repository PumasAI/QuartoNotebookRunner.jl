@testitem "PythonCall evaluates Python code" tags = [:integration] begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    using PythonCall

    nb_mod = QNW.NotebookState.notebook_module()

    # Test basic Python evaluation
    result = QNW._py_expr(nothing, "1 + 2", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test pyconvert(Int, value) == 3

    # Test Python None returns Julia nothing
    result = QNW._py_expr(nothing, "None", LineNumberNode(1, :test), nb_mod)
    value = Core.eval(nb_mod, result)
    @test isnothing(value)
end
