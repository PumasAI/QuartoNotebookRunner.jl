@testitem "render" tags = [:notebook] setup = [RunnerTestSetup] begin
    import QuartoNotebookRunner as QNR
    import JSON
    import JSONSchema
    import .RunnerTestSetup as RTS

    buffer = IOBuffer()
    QNR.render(
        joinpath(@__DIR__, "..", "examples", "cell_types.qmd");
        output = buffer,
        showprogress = false,
    )
    seekstart(buffer)
    json = JSON.parse(buffer)

    @test JSONSchema.validate(RTS.SCHEMA, json) === nothing
end
