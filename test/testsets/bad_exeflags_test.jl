@testitem "bad exeflags" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    s = QNR.Server()
    path = joinpath(@__DIR__, "..", "examples", "bad_exeflags.qmd")
    if VERSION < v"1.8"
        @test_throws QNR.UserError QNR.run!(s, path)
    else
        @test_throws "--unknown-flag" QNR.run!(s, path)
    end
    path = joinpath(@__DIR__, "..", "examples", "bad_juliaup_channel.qmd")
    if VERSION < v"1.8"
        @test_throws QNR.UserError QNR.run!(s, path)
    else
        @test_throws "Invalid Juliaup channel `unknown`" QNR.run!(s, path)
    end
end
