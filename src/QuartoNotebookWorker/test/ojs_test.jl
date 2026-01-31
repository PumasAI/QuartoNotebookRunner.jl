@testitem "ojs_convert basic" begin
    import QuartoNotebookWorker as QNW
    import JSON3  # Triggers extension

    # ojs_convert expects an iterator of name => value pairs
    result = QNW.ojs_convert(pairs((; x = 1, y = "hello")))
    @test length(result) == 2
    @test result[1]["name"] == :x
    @test result[1]["value"] == 1
    @test result[2]["name"] == :y
    @test result[2]["value"] == "hello"
end

@testitem "ojs_convert with Tables" begin
    import QuartoNotebookWorker as QNW
    import JSON3
    import Tables
    import DataFrames: DataFrame

    df = DataFrame(a = [1, 2], b = ["x", "y"])
    result = QNW.ojs_convert(pairs((; mydata = df)))

    @test length(result) == 1
    @test result[1]["name"] == :mydata
    # Should be converted to array of row NamedTuples via Tables extension
    @test result[1]["value"] isa Vector
    @test length(result[1]["value"]) == 2
end
