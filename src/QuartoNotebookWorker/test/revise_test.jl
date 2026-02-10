@testitem "Revise extension loads" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using Revise

    QNW.NotebookState.with_test_context() do
        # Extension should load without error
        @test true
    end
end
