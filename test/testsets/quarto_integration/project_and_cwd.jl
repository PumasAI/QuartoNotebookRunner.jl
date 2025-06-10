include("../../utilities/prelude.jl")

@testset "quarto includes" begin
    # TODO: use quarto_jll for integration tests once modern enough versions are available
    cmd(file) = addenv(
        `quarto render $file --to md`,
        "QUARTO_JULIA_PROJECT" => normpath(joinpath(@__DIR__, "..", "..", "..")),
    )
    outputfile(file) = splitext(file)[1] * ".md"

    project_dir = normpath(joinpath(@__DIR__, "..", "..", "examples", "quarto_integration"))
    # for some reason the quarto project inside the normal test folder structure is not
    # picked up by quarto, so we transfer the files to a separate temp dir first
    mktempdir() do dir
        cp(project_dir, dir; force = true)
        file = joinpath(dir, "project_and_cwd.qmd")
        file_subfolder = joinpath(dir, "subfolder", "project_and_cwd.qmd")

        run(cmd(file))
        run(cmd(file_subfolder))

        output = outputfile(file)
        output_subfolder = outputfile(file_subfolder)

        str_output = read(output, String)
        @test occursin("cwd = $(repr(dir))", str_output)
        @test occursin("projectDir = $(repr(dir))", str_output)

        # subfolder has different cwd but same projectDir
        str_output_subfolder = read(output_subfolder, String)
        @test occursin("cwd = $(repr(joinpath(dir, "subfolder")))", str_output_subfolder)
        @test occursin("projectDir = $(repr(dir))", str_output_subfolder)

        rm(output)
        rm(output_subfolder)

        run(`quarto call engine julia stop`)
    end
end
