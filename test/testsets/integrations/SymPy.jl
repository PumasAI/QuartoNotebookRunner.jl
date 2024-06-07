include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/SymPy.qmd")) do json
    cells = json["cells"]
    cell = cells[4]
    output = cell["outputs"][1]

    @test output["data"]["text/markdown"] == raw"$\frac{\sin^{2}{\left(x \right)}}{2}$"
    @test output["data"]["text/latex"] == raw"$\frac{\sin^{2}{\left(x \right)}}{2}$"
end
