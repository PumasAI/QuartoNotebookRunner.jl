include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/PythonCall.qmd")) do json
    cells = json["cells"]

    @test occursin("PythonCall must be imported", cells[3]["outputs"][1]["traceback"][1])

    @test cells[8]["data"]["outputs"][1]["text/plain"] ==
          "Python: ['PythonCall', 'jl', 'is', 'very', 'useful']"
end
