@testitem "Plots extension renders" tags = [:integration, :julia110] begin
    import QuartoNotebookWorker as QNW
    import Plots

    QNW.NotebookState.OPTIONS[] =
        Dict{String,Any}("format" => Dict("execute" => Dict("fig-dpi" => 100)))
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    QNW.run_package_loading_hooks()

    p = Plots.plot([1, 2, 3])
    result = QNW.render_mimetypes(p, Dict{String,Any}())

    @test haskey(result, "image/png")
    png_data = result["image/png"].data
    @test length(png_data) > 8
    @test png_data[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
end
