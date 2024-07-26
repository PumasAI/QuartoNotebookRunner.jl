using Test, QuartoNotebookWorker

@testset "QuartoNotebookWorker" begin
    # Just a dummy test for now. We can start adding real tests in follow-up PRs
    # that make changes to the worker code.
    @test QuartoNotebookWorker.Packages.is_precompiling() == false
    @test QuartoNotebookWorker._figure_metadata() == (
        fig_width_inch = nothing,
        fig_height_inch = nothing,
        fig_format = nothing,
        fig_dpi = nothing,
    )
end
