@testitem "extract_cell_options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # Basic YAML parsing
    source = """
    #| echo: false
    #| eval: true
    println("hello")
    """
    opts = QNR.extract_cell_options(source; file = "test.qmd", line = 1)
    @test opts["echo"] == false
    @test opts["eval"] == true

    # No options returns empty dict
    source = "println(1)"
    opts = QNR.extract_cell_options(source; file = "test.qmd", line = 1)
    @test isempty(opts)

    # Complex YAML values
    source = """
    #| fig-cap: "Test caption"
    #| layout-ncol: 2
    plot(1:10)
    """
    opts = QNR.extract_cell_options(source; file = "test.qmd", line = 1)
    @test opts["fig-cap"] == "Test caption"
    @test opts["layout-ncol"] == 2
end

@testitem "strip_cell_options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = """
    #| echo: false
    #| eval: true
    println("hello")
    """
    stripped = QNR.strip_cell_options(source)
    @test stripped == "println(\"hello\")\n"

    # No options - returns unchanged
    source = "x = 1"
    stripped = QNR.strip_cell_options(source)
    @test stripped == "x = 1"
end

@testitem "process_cell_source" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = "line1\nline2\nline3"
    lines = QNR.process_cell_source(source)
    @test lines == ["line1\n", "line2\n", "line3"]

    # Empty cell_options returns without YAML prefix
    lines = QNR.process_cell_source(source, Dict{String,Any}())
    @test lines == ["line1\n", "line2\n", "line3"]

    # With cell_options adds YAML prefix
    opts = Dict{String,Any}("echo" => false)
    lines = QNR.process_cell_source("x = 1", opts)
    @test any(l -> contains(l, "#| echo: false"), lines)
    @test lines[end] == "x = 1"
end
