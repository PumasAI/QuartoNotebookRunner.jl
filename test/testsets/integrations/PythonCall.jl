include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/PythonCall.qmd")) do json
    cells = json["cells"]

    cell = cells[8]
    @test occursin("PythonCall", cell["outputs"][1]["data"]["text/plain"])

    cell = cells[11]
    @test occursin("'PythonCall'", cell["outputs"][1]["text"])

    cell = cells[16]
    @test occursin("5", cell["outputs"][1]["data"]["text/plain"])

    cell = cells[17]
    @test occursin("Inline python code: something.", join(cell["source"]))

    cell = cells[22]
    @test occursin("1000", cell["outputs"][1]["data"]["text/plain"])

    cell = cells[27]
    @test occursin("150", cell["outputs"][1]["data"]["text/plain"])
end
