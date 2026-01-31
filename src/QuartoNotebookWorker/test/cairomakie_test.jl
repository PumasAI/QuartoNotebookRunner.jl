@testitem "CairoMakie svg format" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    import CairoMakie

    QNW.NotebookState.OPTIONS[] =
        Dict{String,Any}("format" => Dict("execute" => Dict("fig-format" => "svg")))
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    QNW.run_package_refresh_hooks()

    fig = CairoMakie.Figure()
    CairoMakie.Axis(fig[1, 1])

    result = QNW.render_mimetypes(fig, Dict{String,Any}())
    @test haskey(result, "image/svg+xml")
    # Verify actual SVG content
    svg_data = String(result["image/svg+xml"].data)
    @test startswith(svg_data, "<?xml") || startswith(svg_data, "<svg")
end

@testitem "CairoMakie png format" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    import CairoMakie

    QNW.NotebookState.OPTIONS[] =
        Dict{String,Any}("format" => Dict("execute" => Dict("fig-format" => "png")))
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    QNW.run_package_refresh_hooks()

    fig = CairoMakie.Figure()
    CairoMakie.Axis(fig[1, 1])

    result = QNW.render_mimetypes(fig, Dict{String,Any}())
    @test haskey(result, "image/png")
    # Verify PNG magic bytes
    png_data = result["image/png"].data
    @test length(png_data) > 8
    @test png_data[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
end

@testitem "Makie extension configures size" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    import CairoMakie
    Makie = CairoMakie.Makie

    QNW.NotebookState.OPTIONS[] = Dict{String,Any}(
        "format" => Dict("execute" => Dict("fig-width" => 8, "fig-height" => 6)),
    )
    QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
    QNW.NotebookState.define_notebook_module!()
    QNW.run_package_refresh_hooks()

    theme = Makie.current_default_theme()
    size = theme[:size][]
    @test size[1] ≈ 8 * 96
    @test size[2] ≈ 6 * 96
end

@testitem "CairoMakie dpi affects pixel dimensions" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    import CairoMakie

    for (dpi, expected_width) in [(100, 400), (200, 800)]
        QNW.NotebookState.OPTIONS[] = Dict{String,Any}(
            "format" => Dict(
                "execute" => Dict(
                    "fig-width" => 4,
                    "fig-height" => 3,
                    "fig-dpi" => dpi,
                    "fig-format" => "png",
                ),
            ),
        )
        QNW.NotebookState.CELL_OPTIONS[] = Dict{String,Any}()
        QNW.NotebookState.define_notebook_module!()
        QNW.run_package_refresh_hooks()

        fig = CairoMakie.Figure()
        CairoMakie.Axis(fig[1, 1])
        result = QNW.render_mimetypes(fig, Dict{String,Any}())

        png_data = result["image/png"].data
        @test length(png_data) > 24
        # PNG IHDR width is at bytes 17-20 (1-indexed), big-endian
        width = ntoh(reinterpret(UInt32, @view(png_data[17:20]))[])
        @test width == expected_width
    end
end
