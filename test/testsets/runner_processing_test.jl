@testitem "process_results extracts PNG metadata" tags = [:unit] begin
    import QuartoNotebookRunner as QNR
    import Base64

    MimeResult = QNR.WorkerIPC.MimeResult

    # Helper: create minimal PNG with pHYs chunk for DPI testing
    function make_test_png(width, height, dpi)
        buf = IOBuffer()
        # PNG signature
        write(buf, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        # IHDR chunk
        ihdr_data = IOBuffer()
        write(ihdr_data, hton(UInt32(width)))
        write(ihdr_data, hton(UInt32(height)))
        write(ihdr_data, UInt8(8))   # bit depth
        write(ihdr_data, UInt8(2))   # RGB
        write(ihdr_data, UInt8(0))   # compression
        write(ihdr_data, UInt8(0))   # filter
        write(ihdr_data, UInt8(0))   # interlace
        ihdr = take!(ihdr_data)
        write(buf, hton(UInt32(length(ihdr))))
        write(buf, b"IHDR")
        write(buf, ihdr)
        write(buf, hton(UInt32(0)))  # CRC (fake)
        # pHYs chunk (pixels per meter)
        ppm = round(UInt32, dpi / 0.0254)
        phys_data = IOBuffer()
        write(phys_data, hton(ppm))
        write(phys_data, hton(ppm))
        write(phys_data, UInt8(1))   # meter unit
        phys = take!(phys_data)
        write(buf, hton(UInt32(length(phys))))
        write(buf, b"pHYs")
        write(buf, phys)
        write(buf, hton(UInt32(0)))
        # IDAT + IEND
        write(buf, hton(UInt32(0)))
        write(buf, b"IDAT")
        write(buf, hton(UInt32(0)))
        write(buf, hton(UInt32(0)))
        write(buf, b"IEND")
        write(buf, hton(UInt32(0)))
        take!(buf)
    end

    # 800x600 at 192 DPI -> 400x300 CSS pixels
    png_bytes = make_test_png(800, 600, 192)

    results =
        Dict{String,MimeResult}("image/png" => MimeResult("image/png", false, png_bytes))

    processed = QNR.process_results(results)

    @test haskey(processed.metadata, "image/png")
    @test processed.metadata["image/png"].width == 400
    @test processed.metadata["image/png"].height == 300
    @test haskey(processed.data, "image/png")  # base64 encoded
end

@testitem "process_results handles multiple MIME types" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    MimeResult = QNR.WorkerIPC.MimeResult

    results = Dict{String,MimeResult}(
        "text/plain" => MimeResult("text/plain", false, Vector{UInt8}("hello")),
        "text/html" => MimeResult("text/html", false, Vector{UInt8}("<b>hello</b>")),
    )

    processed = QNR.process_results(results)

    @test processed.data["text/plain"] == "hello"
    @test processed.data["text/html"] == "<b>hello</b>"
    @test isempty(processed.errors)
end

@testitem "process_results collects show errors" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    MimeResult = QNR.WorkerIPC.MimeResult

    results = Dict{String,MimeResult}(
        "text/plain" => MimeResult(
            "text/plain",
            true,
            Vector{UInt8}("MethodError: no method matching show(...)"),
        ),
    )

    processed = QNR.process_results(results)

    @test length(processed.errors) == 1
    @test processed.errors[1].output_type == "error"
    @test processed.errors[1].ename == "text/plain showerror"
end

@testitem "process_results passes through markdown" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    MimeResult = QNR.WorkerIPC.MimeResult

    # typst raw block example
    typst_content = "```{=typst}\n#figure(...)\n```"
    results = Dict{String,MimeResult}(
        "text/markdown" =>
            MimeResult("text/markdown", false, Vector{UInt8}(typst_content)),
    )

    processed = QNR.process_results(results)

    @test processed.data["text/markdown"] == typst_content
end

@testitem "process_results handles JSON content" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    MimeResult = QNR.WorkerIPC.MimeResult

    json_content = """{"key": "value", "number": 42}"""
    results = Dict{String,MimeResult}(
        "application/json" =>
            MimeResult("application/json", false, Vector{UInt8}(json_content)),
    )

    processed = QNR.process_results(results)

    @test processed.data["application/json"]["key"] == "value"
    @test processed.data["application/json"]["number"] == 42
end

@testitem "process_results handles PDF content" tags = [:unit] begin
    import QuartoNotebookRunner as QNR
    import Base64

    MimeResult = QNR.WorkerIPC.MimeResult

    # Fake PDF content
    pdf_bytes = Vector{UInt8}("%PDF-1.4 fake content")
    results = Dict{String,MimeResult}(
        "application/pdf" => MimeResult("application/pdf", false, pdf_bytes),
    )

    processed = QNR.process_results(results)

    @test processed.data["application/pdf"] == Base64.base64encode(pdf_bytes)
end

@testitem "process_results unknown MIME returns nothing" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    MimeResult = QNR.WorkerIPC.MimeResult

    results = Dict{String,MimeResult}(
        "application/x-custom" =>
            MimeResult("application/x-custom", false, Vector{UInt8}("data")),
    )

    processed = QNR.process_results(results)

    @test !haskey(processed.data, "application/x-custom")
end

@testitem "process_cell_source without options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = "x = 1\ny = 2"
    result = QNR.process_cell_source(source)
    @test result == ["x = 1\n", "y = 2"]
end

@testitem "process_cell_source with new options only" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = "x = 1"
    result = QNR.process_cell_source(source, Dict("echo" => false))
    @test result[1] == "#| echo: false\n"
    @test result[2] == "x = 1"
end

@testitem "process_cell_source merges existing and new options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = "#| label: foo\nx = 1"
    result = QNR.process_cell_source(source, Dict("echo" => false))
    # Should have both options, and source stripped of original options
    @test any(contains("echo: false"), result)
    @test any(contains("label: \"foo\""), result)  # YAML quotes strings
    @test any(==("x = 1"), result)
    # Original option line should not be duplicated
    @test count(contains("label"), result) == 1
end

@testitem "process_cell_source new options override existing" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    source = "#| echo: fenced\nx = 1"
    result = QNR.process_cell_source(source, Dict("echo" => false))
    # New value should win
    @test any(contains("echo: false"), result)
    @test !any(contains("echo: fenced"), result)
    # Only one echo key
    @test count(contains("echo"), result) == 1
end

@testitem "_add_language_prefix_cell! standard fencing" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    cells = []
    chunk = (; source = "x = 1", file = "test.qmd", line = 1)
    QNR._add_language_prefix_cell!(cells, chunk, 1, 1, false, :python, false)

    @test length(cells) == 1
    source = join(cells[1].source)
    @test contains(source, "```python")
    @test contains(source, "x = 1")
    @test !contains(source, "{{")
end

@testitem "_add_language_prefix_cell! fenced mode" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    cells = []
    chunk = (; source = "x = 1", file = "test.qmd", line = 1)
    QNR._add_language_prefix_cell!(cells, chunk, 1, 1, false, :python, true)

    @test length(cells) == 1
    source = join(cells[1].source)
    @test contains(source, "```{{python}}")
    @test contains(source, "x = 1")
end

@testitem "_add_language_prefix_cell! strips cell options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    cells = []
    chunk = (; source = "#| label: foo\nx = 1", file = "test.qmd", line = 1)
    QNR._add_language_prefix_cell!(cells, chunk, 1, 1, false, :r, false)

    @test length(cells) == 1
    source = join(cells[1].source)
    @test contains(source, "```r")
    @test contains(source, "x = 1")
    @test !contains(source, "label")
end

@testitem "_get_user_echo from cell_options" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    chunk = (; source = "x = 1", file = "test.qmd", line = 1)

    # cell_options has echo
    @test QNR._get_user_echo(Dict("echo" => false), chunk) == false
    @test QNR._get_user_echo(Dict("echo" => "fenced"), chunk) == "fenced"
end

@testitem "_get_user_echo from source" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # No cell_options, extract from source
    chunk = (; source = "#| echo: fenced\nx = 1", file = "test.qmd", line = 1)
    @test QNR._get_user_echo(Dict(), chunk) == "fenced"

    # No echo in source, default to true
    chunk = (; source = "x = 1", file = "test.qmd", line = 1)
    @test QNR._get_user_echo(Dict(), chunk) == true
end
