@testitem "Cell construction" begin
    import QuartoNotebookWorker as QNW

    # Cell with content only - code is empty, echo is false by default
    cell = QNW.Cell(42)
    @test cell.code == ""
    @test cell.options["echo"] == false

    # Cell with content and explicit code
    cell = QNW.Cell(() -> 42; code = "x = 42")
    @test cell.code == "x = 42"
    @test !haskey(cell.options, "echo")  # echo not set when code provided

    # Cell with options
    cell = QNW.Cell(42; options = Dict{String,Any}("output" => false))
    @test cell.options["output"] == false
    @test cell.options["echo"] == false  # still set because no code
end

@testitem "_is_expanded validation" begin
    import QuartoNotebookWorker as QNW

    # Valid: returns Vector{Cell}
    original = "something"
    expanded = [QNW.Cell(1)]
    @test QNW._is_expanded(original, expanded) == true

    # Valid: returns nothing (no expansion)
    @test QNW._is_expanded(original, nothing) == false

    # Invalid: same object returned - throws error
    @test_throws QNW.CellExpansionError QNW._is_expanded(original, original)

    # Invalid: not a Vector{Cell} - throws error
    @test_throws QNW.CellExpansionError QNW._is_expanded(original, [1, 2, 3])
end
