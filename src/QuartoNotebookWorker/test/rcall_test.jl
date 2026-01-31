@testitem "RCall extension hooks" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using RCall

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()

    # Test R evaluation works
    result = RCall.rcopy(Int, RCall.reval("1 + 2"))
    @test result == 3

    # Test refresh clears R workspace
    RCall.reval("test_var <- 42")
    @test RCall.rcopy(Int, RCall.reval("test_var")) == 42

    # Refresh hooks clear R workspace (extension registers via add_package_refresh_hook!)
    QNW.run_package_refresh_hooks()

    # After refresh, test_var should not exist
    @test_throws RCall.REvalError RCall.reval("test_var")
end
