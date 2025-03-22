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

    cell = cells[30]
    @test isempty(cell["outputs"])

    cell = cells[33]
    traceback = cell["outputs"][1]["traceback"]
    @test occursin("division by zero", traceback[1])
    @test occursin("PythonCall.qmd:54", traceback[4])
    @test occursin("PythonCall.qmd:58", traceback[end])

    cell = cells[36]
    traceback = cell["outputs"][1]["traceback"]
    @test occursin("unmatched ']'", traceback[1])
    @test occursin("PythonCall.qmd, line 62", traceback[1])
    @test occursin("ast.py", traceback[end])

    cell = cells[39]
    output = cell["outputs"][1]
    @test output["name"] == "stdout"
    @test occursin("Define the builtin 'help'.", output["text"])
end
