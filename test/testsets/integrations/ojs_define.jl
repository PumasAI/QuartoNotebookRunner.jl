include("../../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../../examples/integrations/ojs_define.qmd")) do json
    cells = json["cells"]

    cell = cells[2]
    @test contains(cell["outputs"][1]["data"]["text/plain"], "ojs_define")

    cell = cells[8]
    @test !isempty(cell["outputs"][1]["data"]["text/plain"])
    @test !isempty(cell["outputs"][1]["data"]["text/html"])
end
