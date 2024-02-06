include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/cell_dependencies.qmd")) do json
    cells = json["cells"]

    cell = cells[2]
    @test cell["outputs"][1]["data"]["text/plain"] == "1"

    cell = cells[4]
    @test cell["outputs"][1]["data"]["text/plain"] == "2"

    cell = cells[6]
    traceback = join(cell["outputs"][1]["traceback"], "\n")
    @test count("not defined", traceback) == 1

    cell = cells[8]
    @test cell["outputs"][1]["data"]["text/plain"] == "Any[]"

    cell = cells[10]
    @test contains(cell["outputs"][1]["data"]["text/plain"], "Vector{Any}")
    @test contains(cell["outputs"][1]["data"]["text/plain"], ":item")

    cell = cells[12]
    @test cell["outputs"][1]["data"]["text/plain"] == "\"item\""
end
