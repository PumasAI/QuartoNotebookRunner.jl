@testitem "seeded random numbers are consistent across runs" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    notebook = joinpath(@__DIR__, "..", "examples", "random_seed", "random_seed.qmd")

    server = QNR.Server()

    jsons = map(1:2) do _
        QNR.run!(server, notebook; showprogress = false)
    end

    _output(cell) = only(cell.outputs).data["text/plain"]

    @test tryparse(Float64, _output(jsons[1].cells[2])) !== nothing
    @test tryparse(Float64, _output(jsons[1].cells[4])) !== nothing
    @test tryparse(Float64, _output(jsons[1].cells[6])) !== nothing

    @test length(unique([_output(jsons[1].cells[i]) for i in [2, 4, 6]])) == 3

    @test _output(jsons[1].cells[2]) == _output(jsons[2].cells[2])
    @test _output(jsons[1].cells[4]) == _output(jsons[2].cells[4])
    @test _output(jsons[1].cells[6]) == _output(jsons[2].cells[6])

    QNR.close!(server)
end
