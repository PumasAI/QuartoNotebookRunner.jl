include("../utilities/prelude.jl")

@testset "seeded random numbers are consistent across runs" begin
    mktempdir() do dir
        content = read(joinpath(@__DIR__, "../examples/random_seed.qmd"), String)
        cd(dir) do
            server = QuartoNotebookRunner.Server()
            write("notebook.qmd", content)

            jsons = map(1:2) do _
                QuartoNotebookRunner.run!(
                    server,
                    "notebook.qmd";
                    showprogress = false,
                )
            end

            _output(cell) = only(cell.outputs).data["text/plain"]

            @test tryparse(Float64, _output(jsons[1].cells[2])) !== nothing
            @test tryparse(Float64, _output(jsons[1].cells[4])) !== nothing
            @test tryparse(Float64, _output(jsons[1].cells[6])) !== nothing

            @test length(unique([_output(jsons[1].cells[i]) for i in [2, 4, 6]])) == 3

            @test _output(jsons[1].cells[2]) == _output(jsons[2].cells[2])
            @test _output(jsons[1].cells[4]) == _output(jsons[2].cells[4])
            @test _output(jsons[1].cells[6]) == _output(jsons[2].cells[6])

            close!(server)
        end
    end
end
