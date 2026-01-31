@testitem "_escape_markdown" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # Backslash escaping of special chars
    @test QNR._escape_markdown("*bold*") == "\\*bold\\*"
    @test QNR._escape_markdown("_italic_") == "\\_italic\\_"
    @test QNR._escape_markdown("`code`") == "\\`code\\`"
    @test QNR._escape_markdown("[link](url)") == "\\[link\\]\\(url\\)"
    @test QNR._escape_markdown("# heading") == "\\# heading"

    # Bytes input
    @test QNR._escape_markdown(Vector{UInt8}("*test*")) == "\\*test\\*"

    # No special chars unchanged
    @test QNR._escape_markdown("plain text") == "plain text"
end

@testitem "format_seconds" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    # Seconds
    @test QNR.format_seconds(1) == "1 second"
    @test QNR.format_seconds(30) == "30 seconds"
    @test QNR.format_seconds(59) == "59 seconds"

    # Minutes
    @test QNR.format_seconds(60) == "1 minute"
    @test QNR.format_seconds(90) == "1 minute 30 seconds"
    @test QNR.format_seconds(120) == "2 minutes"
    @test QNR.format_seconds(3599) == "59 minutes 59 seconds"

    # Hours
    @test QNR.format_seconds(3600) == "1 hour"
    @test QNR.format_seconds(3661) == "1 hour 1 minute 1 second"
    @test QNR.format_seconds(7200) == "2 hours"
end
