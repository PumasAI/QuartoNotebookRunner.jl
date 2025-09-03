if VERSION >= v"1.10"
    include("../../utilities/prelude.jl")

    @testset "RCall refresh" begin
        s = Server()

        base_file =
            joinpath(@__DIR__, "..", "..", "examples", "integrations", "RCall_refresh.qmd")
        copy = joinpath(dirname(base_file), "RCall_refresh_copy.qmd")

        try
            # need the file in this dir so the relative --project path is correct
            cp(base_file, copy)
            json = run!(s, copy)

            @test json.cells[end-1].outputs[1].data["text/plain"] == "4.0"

            original = read(copy, String)
            modified = replace(original, "x <- 1" => "NULL")

            open(copy, "w") do io
                print(io, modified)
            end

            json = run!(s, copy)
            @test json.cells[end-1].outputs[1].traceback[1] ==
                  "REvalError: Error: object 'x' not found"
        finally
            rm(copy)
        end
    end
end
