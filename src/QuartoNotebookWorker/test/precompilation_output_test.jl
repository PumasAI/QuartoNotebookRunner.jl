@testitem "strip worker precompilation" tags = [:integration] begin
    import QuartoNotebookWorker as QNW

    strip(output, extensions = ["QuartoNotebookWorkerJSONExt"]) =
        QNW.strip_worker_precompilation(output, extensions)

    report = """
    Precompiling packages...
       1268.0 ms  ✓ QuartoNotebookWorkerJSONExt (serial)
      1 dependency successfully precompiled in 1 seconds
    """

    # Nothing loaded during the cell means nothing reported about it.
    @test strip(report, String[]) == report

    @test isempty(Base.strip(strip(report)))

    others = """
    Precompiling packages...
       1268.0 ms  ✓ Example
      1 dependency successfully precompiled in 1 seconds
    """
    @test strip(others) == others

    mixed = """
    Precompiling packages...
       1268.0 ms  ✓ QuartoNotebookWorkerJSONExt (serial)
        836.1 ms  ✓ Example
      2 dependencies successfully precompiled in 2 seconds
    """
    stripped = strip(mixed)
    @test !occursin("QuartoNotebookWorkerJSONExt", stripped)
    @test occursin("✓ Example", stripped)
    @test occursin("Precompiling packages...", stripped)

    # A cell can produce one report per package it loads.
    consecutive = """
    Precompiling packages...
       5251.9 ms  ✓ Example
      1 dependency successfully precompiled in 5 seconds
    Precompiling packages...
       1268.0 ms  ✓ QuartoNotebookWorkerJSONExt (serial)
      1 dependency successfully precompiled in 1 seconds
    """
    stripped = strip(consecutive)
    @test count("Precompiling packages...", stripped) == 1
    @test occursin("✓ Example", stripped)

    # A cell of `using` lines reports each extension it reaches in turn.
    imports = """
    Precompiling packages...
       4126.8 ms  ✓ QuartoNotebookWorkerTablesExt (serial)
      1 dependency successfully precompiled in 5 seconds
    Precompiling packages...
       2752.8 ms  ✓ QuartoNotebookWorkerJSONExt (serial)
      1 dependency successfully precompiled in 4 seconds
    Precompiling packages...
      13587.9 ms  ✓ QuartoNotebookWorkerCairoMakieExt (serial)
      1 dependency successfully precompiled in 14 seconds
    """
    @test isempty(
        Base.strip(
            strip(
                imports,
                [
                    "QuartoNotebookWorkerTablesExt",
                    "QuartoNotebookWorkerJSONExt",
                    "QuartoNotebookWorkerCairoMakieExt",
                ],
            ),
        ),
    )

    # Only the report is ours to remove.
    interleaved = """
    Precompiling packages...
    printed by the cell
       1268.0 ms  ✓ QuartoNotebookWorkerJSONExt (serial)
      1 dependency successfully precompiled in 1 seconds
    """
    @test Base.strip(strip(interleaved)) == "printed by the cell"

    # Cell output that writes about precompilation is not a report.
    lookalike = """
    Precompiling my model...
      QuartoNotebookWorkerJSONExt is an implementation detail
    """
    @test strip(lookalike) == lookalike

    failed = """
    Precompiling packages...
        836.1 ms  ✗ QuartoNotebookWorkerJSONExt
      1 dependency errored.
    """
    @test strip(failed) == failed

    # Colour, other packages, and a report per package, as a real cell of
    # `using` lines produces on a fresh depot.
    tick = "\e[32m  ✓ \e[39m"
    header = "\e[32m\e[1mPrecompiling\e[22m\e[39m packages...\n"
    realistic =
        header *
        "   4126.8 ms$(tick)SummaryTables\n" *
        "   2477.7 ms$(tick)QuartoNotebookWorkerTablesExt\e[90m (serial)\e[39m\n" *
        "  2 dependencies successfully precompiled in 7 seconds\n" *
        header *
        "  13587.9 ms$(tick)QuartoNotebookWorkerCairoMakieExt\e[90m (serial)\e[39m\n" *
        "  1 dependency successfully precompiled in 14 seconds\n" *
        header *
        "   9001.0 ms$(tick)AlgebraOfGraphics\n" *
        "  1 dependency successfully precompiled in 9 seconds\n"
    stripped = strip(
        realistic,
        ["QuartoNotebookWorkerTablesExt", "QuartoNotebookWorkerCairoMakieExt"],
    )
    @test !occursin("QuartoNotebookWorker", stripped)
    @test occursin("$(tick)SummaryTables", stripped)
    @test occursin("$(tick)AlgebraOfGraphics", stripped)
    @test count("Precompiling", stripped) == 2

    # Colour codes surround the marker and the name in a real report.
    coloured =
        "\e[32m\e[1mPrecompiling\e[22m\e[39m packages...\n" *
        "   1268.0 ms\e[32m  ✓ \e[39mQuartoNotebookWorkerJSONExt\e[90m (serial)\e[39m\n" *
        "  1 dependency successfully precompiled in 1 seconds\n"
    @test isempty(Base.strip(strip(coloured)))
end
