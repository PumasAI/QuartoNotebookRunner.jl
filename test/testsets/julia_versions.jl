include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/julia-1.9.4.qmd")) do json
    cells = json["cells"]
    @test cells[end]["outputs"][1]["data"]["text/plain"] == repr(v"1.9.4")
    @test json["metadata"]["language_info"]["version"] == "1.9.4"
end
test_example(joinpath(@__DIR__, "../examples/julia-1.10.7.qmd")) do json
    cells = json["cells"]
    @test cells[end]["outputs"][1]["data"]["text/plain"] == repr(v"1.10.7")
    @test json["metadata"]["language_info"]["version"] == "1.10.7"
end
test_example(joinpath(@__DIR__, "../examples/julia-1.11.2.qmd")) do json
    cells = json["cells"]
    @test cells[end]["outputs"][1]["data"]["text/plain"] == repr(v"1.11.2")
    @test json["metadata"]["language_info"]["version"] == "1.11.2"
end
