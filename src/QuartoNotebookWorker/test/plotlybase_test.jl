@testitem "PlotlyBase expand" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    import PlotlyBase

    QNW.NotebookState.with_test_context() do
        QNW.run_package_refresh_hooks()

        p = PlotlyBase.Plot(PlotlyBase.scatter(x = [1, 2, 3], y = [1, 2, 3]))

        # First plot should expand to 2 cells (preamble + plot)
        cells = QNW.expand(p)
        @test cells isa Vector{QNW.Cell}
        @test length(cells) == 2

        # Second plot should expand to 1 cell (just plot)
        cells2 = QNW.expand(p)
        @test length(cells2) == 1
    end
end
