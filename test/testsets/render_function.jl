include("../utilities/prelude.jl")

@testset "render" begin
    buffer = IOBuffer()
    QuartoNotebookRunner.render(
        joinpath(@__DIR__, "../examples/cell_types.qmd");
        output = buffer,
        showprogress = false,
    )
    seekstart(buffer)
    json = JSON3.read(buffer, Any)

    @test JSONSchema.validate(SCHEMA, json) === nothing
end
