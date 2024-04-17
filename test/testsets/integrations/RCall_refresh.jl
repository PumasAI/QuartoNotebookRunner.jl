include("../../utilities/prelude.jl")

@testset "RCall refresh" begin
    s = Server()

    base_file =
        joinpath(@__DIR__, "..", "..", "examples", "integrations", "RCall_refresh.qmd")
    copy = joinpath(dirname(base_file), "RCall_refresh_copy.qmd")

    function _cells(file)
        io = IOBuffer()
        run!(s, file; output = io)
        seekstart(io)
        JSON3.read(io, Any)["cells"]
    end

    try
        # need the file in this dir so the relative --project path is correct
        cp(base_file, copy)
        cells = _cells(copy)

        @test cells[end]["outputs"][1]["data"]["text/plain"] == "4.0"

        modified = replace(read(copy, String), r"delete this block[\s\S]*?```\n" => "")

        open(copy, "w") do io
            print(io, modified)
        end

        cells = _cells(copy)
        @test cells[end]["outputs"][1]["traceback"][1] ==
              "REvalError: Error: object 'x' not found"
    finally
        rm(copy)
    end
end
