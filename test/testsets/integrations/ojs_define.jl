if VERSION >= v"1.10"
    include("../../utilities/prelude.jl")

    test_example(
        joinpath(@__DIR__, "../../examples/integrations/ojs_define/no_imports.qmd"),
    ) do json
        cells = json["cells"]
        cell = cells[2]
        @test length(cell["outputs"]) == 1
        @test contains(
            cell["outputs"][1]["text"],
            "Please import either JSON.jl or JSON3.jl",
        )
    end

    for file in ("json", "json3", "both")
        test_example(
            joinpath(
                @__DIR__,
                "../../examples/integrations/ojs_define/$(file)_imported.qmd",
            ),
        ) do json
            cells = json["cells"]

            function extract_json(str)
                str = replace(str, "<script type='ojs-define'>" => "")
                str = replace(str, "</script>" => "")
                return JSON3.read(str, Dict{String,Any})
            end

            cell = cells[4]
            data = cell["outputs"][1]["data"]
            @test haskey(data, "text/html")
            @test contains(data["text/html"], "<script type='ojs-define'>")
            obj = extract_json(data["text/html"])
            @test obj["contents"][1] == Dict("name" => "key", "value" => "value")

            for (nth, name) in (8 => "table", 12 => "df")
                cell = cells[nth]
                data = cell["outputs"][1]["data"]
                @test haskey(data, "text/html")
                @test contains(data["text/html"], "<script type='ojs-define'>")
                obj = extract_json(data["text/html"])
                @test obj["contents"][1]["name"] == name
                @test obj["contents"][1]["value"][1] == Dict("a" => 1)
                @test obj["contents"][1]["value"][2] == Dict("a" => 2)
                @test obj["contents"][1]["value"][3] == Dict("a" => 3)
            end
        end
    end
end
