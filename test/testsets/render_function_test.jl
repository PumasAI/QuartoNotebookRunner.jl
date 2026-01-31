@testitem "render" tags = [:notebook] setup = [RunnerTestSetup] begin
    import QuartoNotebookRunner as QNR
    import JSON3
    import JSONSchema
    import .RunnerTestSetup as RTS

    buffer = IOBuffer()
    QNR.render(
        joinpath(@__DIR__, "..", "examples", "cell_types.qmd");
        output = buffer,
        showprogress = false,
    )
    seekstart(buffer)
    json = JSON3.read(buffer, Any)

    @test JSONSchema.validate(RTS.SCHEMA, json) === nothing
end
