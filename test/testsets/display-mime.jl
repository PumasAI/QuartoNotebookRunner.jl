include("../utilities/prelude.jl")

test_example(joinpath(@__DIR__, "../examples/display-mime.qmd")) do json
    cells = json["cells"]
    @test length(cells) == 5
    for each in (2, 4)
        cell = cells[each]
        outputs = cell["outputs"]
        @test length(outputs) == 1
        text_html = outputs[1]["data"]["text/html"]
        @test text_html == "<p></p>"
    end
end
