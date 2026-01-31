@testitem "_extract_timeout" tags = [:unit] begin
    import QuartoNotebookRunner as QNR

    D = Dict{String,Any}
    make_opts(daemon) = D("format" => D("execute" => D("daemon" => daemon)))

    # true -> default 300s
    @test QNR._extract_timeout(make_opts(true)) == 300.0

    # false -> 0
    @test QNR._extract_timeout(make_opts(false)) == 0.0

    # numeric value
    @test QNR._extract_timeout(make_opts(60)) == 60.0
    @test QNR._extract_timeout(make_opts(0)) == 0.0

    # negative throws
    @test_throws ArgumentError QNR._extract_timeout(make_opts(-1))

    # invalid type throws
    @test_throws ArgumentError QNR._extract_timeout(make_opts("invalid"))
end
