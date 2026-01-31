@testitem "Worker timeouts" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    s = QNR.Server()
    base_file = joinpath(@__DIR__, "..", "examples", "timeout.qmd")
    QNR.run!(s, base_file)
    @test length(s.workers) == 0
    mktempdir() do dir
        zero_file = joinpath(dir, "zero.qmd")
        open(zero_file, "w") do io
            println(io, replace(read(base_file, String), "false" => "0"))
        end
        QNR.run!(s, zero_file)
        @test length(s.workers) == 0

        five_file = joinpath(dir, "five.qmd")
        open(five_file, "w") do io
            println(io, replace(read(base_file, String), "false" => "5"))
        end
        QNR.run!(s, five_file)
        @test length(s.workers) == 1
        sleep(3)
        @test length(s.workers) == 1
        sleep(3)
        @test length(s.workers) == 0
    end
end
