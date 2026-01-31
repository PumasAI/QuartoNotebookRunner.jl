@testitem "rget nested lookup" begin
    import QuartoNotebookWorker as QNW

    d = Dict("a" => Dict("b" => Dict("c" => 42)))
    @test QNW.rget(d, ("a", "b", "c"), 0) == 42
    @test QNW.rget(d, ("a", "b", "x"), 0) == 0
    @test QNW.rget(d, ("x",), 0) == 0
    @test QNW.rget(d, (), d) === d
end

@testitem "_figure_metadata" begin
    import QuartoNotebookWorker as QNW

    # Empty options
    QNW.NotebookState.OPTIONS[] = Dict{String,Any}()
    fm = QNW._figure_metadata()
    @test fm.fig_width_inch === nothing
    @test fm.fig_height_inch === nothing
    @test fm.fig_format === nothing
    @test fm.fig_dpi === nothing

    # With values
    QNW.NotebookState.OPTIONS[] = Dict{String,Any}(
        "format" => Dict(
            "execute" => Dict(
                "fig-width" => 6,
                "fig-height" => 4,
                "fig-dpi" => 150,
                "fig-format" => "png",
            ),
        ),
    )
    fm = QNW._figure_metadata()
    @test fm.fig_width_inch == 6
    @test fm.fig_height_inch == 4
    @test fm.fig_dpi == 150
    @test fm.fig_format == "png"
end

@testitem "_getproperty" begin
    import QuartoNotebookWorker as QNW

    struct TestGetPropObj
        x::Int
    end

    obj = TestGetPropObj(42)

    # Property exists - return it
    @test QNW._getproperty(obj, :x, 0) == 42

    # Property missing - return fallback
    @test QNW._getproperty(obj, :missing, 99) == 99

    # Property missing with callable fallback
    @test QNW._getproperty(() -> -1, obj, :missing) == -1
end
