@testitem "parameters" tags = [:notebook] setup = [RunnerTestSetup] begin
    import .RunnerTestSetup as RTS
    import QuartoNotebookRunner as QNR

    json, server = RTS.run_notebook(joinpath(@__DIR__, "..", "examples", "parameters.qmd"))
    RTS.validate_notebook(json)

    cells = json["cells"]

    @test cells[2]["outputs"][1]["data"]["text/plain"] == "1"
    @test cells[4]["outputs"][1]["data"]["text/plain"] == "2.0"
    @test cells[6]["outputs"][1]["data"]["text/plain"] == "\"some string\""
    @test cells[8]["outputs"][1]["data"]["text/plain"] == "\"some other string\""
    @test cells[10]["outputs"][1]["text"] == "[\"string\", \"array\"]"
    @test cells[12]["outputs"][1]["text"] == "[1, 2, 3]"
    @test cells[14]["outputs"][1]["data"]["text/plain"] == "1"
    @test cells[16]["outputs"][1]["data"]["text/plain"] == "2"
    @test cells[18]["outputs"][1]["output_type"] == "error"
    traceback = cells[18]["outputs"][1]["traceback"][1]
    @test contains(traceback, "invalid")
    @test contains(traceback, "constant")

    QNR.close!(server)
end

@testitem "parameters via options" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    s = QNR.Server()
    options = Dict{String,Any}(
        "params" => Dict("a" => 7, "c" => "cli override"),
        "format" => Dict(
            "metadata" =>
                Dict("params" => Dict("a" => 5, "b" => 6.0, "g" => Dict("a" => 4))),
        ),
    )
    json = QNR.run!(s, joinpath(@__DIR__, "..", "examples", "parameters.qmd"); options)

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

@testitem "Invalid parameters" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    s = QNR.Server()
    options = Dict{String,Any}("params" => Dict("invalid identifier" => 7))
    @test_throws ArgumentError(
        "Found parameter key that is not a  valid Julia identifier: \"invalid identifier\".",
    ) QNR.run!(s, joinpath(@__DIR__, "..", "examples", "parameters.qmd"); options)
end
