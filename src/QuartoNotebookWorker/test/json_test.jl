@testitem "JSON write functions" tags = [:integration] begin
    import QuartoNotebookWorker as QNW
    using JSON
    using JSON3

    # JSON extension provides _json_write
    json_fn = QNW._json_write(nothing)
    @test json_fn === JSON.print

    # JSON3 extension provides _json3_write
    json3_fn = QNW._json3_write(nothing)
    @test json3_fn === JSON3.write

    # _json_writer prefers JSON3
    @test QNW._json_writer() === JSON3.write
end
