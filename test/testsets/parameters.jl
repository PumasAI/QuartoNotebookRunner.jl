include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/parameters.qmd")) do json
    cells = json["cells"]

    @test cells[2]["outputs"][1]["data"]["text/plain"] == "1"
    @test cells[4]["outputs"][1]["data"]["text/plain"] == "2.0"
    @test cells[6]["outputs"][1]["data"]["text/plain"] == "\"some string\""
    @test cells[8]["outputs"][1]["data"]["text/plain"] == "\"some other string\""
    @test cells[10]["outputs"][1]["text"] == "[\"string\", \"array\"]"
    @test cells[12]["outputs"][1]["text"] == "[1, 2, 3]"
    @test cells[14]["outputs"][1]["data"]["text/plain"] == "1"
    @test cells[16]["outputs"][1]["data"]["text/plain"] == "2"
end

@testset "parameters via options" begin
    s = Server()
    options = Dict{String,Any}(
        "params" => Dict("a" => 7, "c" => "cli override"),
        "format" => Dict(
            "metadata" =>
                Dict("params" => Dict("a" => 5, "b" => 6.0, "g" => Dict("a" => 4))),
        ),
    )
    json = QuartoNotebookRunner.run!(
        s,
        joinpath(@__DIR__, "../examples/parameters.qmd");
        options,
    )

    cells = json.cells

    @test cells[2].outputs[1].data["text/plain"] == "7"
    @test cells[4].outputs[1].data["text/plain"] == "6.0"
    @test cells[6].outputs[1].data["text/plain"] == "\"cli override\""
    @test cells[8].outputs[1].data["text/plain"] == "\"some other string\""
    @test cells[10].outputs[1].text == "[\"string\", \"array\"]"
    @test cells[12].outputs[1].text == "[1, 2, 3]"
    @test cells[14].outputs[1].data["text/plain"] == "4"
    @test cells[16].outputs[1].data["text/plain"] == "2"
end

@testset "Invalid parameters" begin
    s = Server()
    options = Dict{String,Any}("params" => Dict("invalid identifier" => 7))
    @test_throws ArgumentError(
        "Found parameter key that is not a  valid Julia identifier: \"invalid identifier\".",
    ) QuartoNotebookRunner.run!(
        s,
        joinpath(@__DIR__, "../examples/parameters.qmd");
        options,
    )
end
