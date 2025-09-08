include("../../utilities/prelude.jl")

@testset "quarto project root env variable" begin
    dir = joinpath(@__DIR__, "..", "..", "examples", "quarto_integration")
    file_a = joinpath(dir, "projectA", "projectA.qmd")
    file_b = joinpath(dir, "projectB", "projectB.qmd")
    # TODO: use quarto_jll for integration tests once modern enough versions are available
    cmd(file) = addenv(
        `quarto render $file --to md`,
        "QUARTO_JULIA_PROJECT" => normpath(joinpath(@__DIR__, "..", "..", "..")),
    )
    # check that the project is not the same for both even though 
    run(cmd(file_a))

    function server_start_time_and_pid()
        status = readchomp(`quarto call engine julia status`)
        started_at = something(match(r"started at: ([\d\:]+)", status))[1]
        pid = something(match(r"pid: (\d+)", status))[1]
        return started_at, pid
    end

    time_pid_a = server_start_time_and_pid()
    run(cmd(file_b))
    time_pid_b = server_start_time_and_pid()

    # make sure server process hasn't changed so the env variable
    # can't have been updated this way
    @test time_pid_a == time_pid_b

    outputfile_a = joinpath(dir, "projectA", "projectA.md")
    outputfile_b = joinpath(dir, "projectB", "projectB.md")
    @test occursin(r"QUARTO_PROJECT_ROOT.*?projectA", read(outputfile_a, String))
    @test occursin(r"QUARTO_PROJECT_ROOT.*?projectB", read(outputfile_b, String))
    rm(outputfile_a)
    rm(outputfile_b)
end
