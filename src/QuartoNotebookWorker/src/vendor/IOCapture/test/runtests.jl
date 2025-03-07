using IOCapture
using Test, Random

# hasfield was added in Julia 1.2. This definition borrowed from Compat.jl (MIT)
# Note: this can not be inside the testset
(VERSION < v"1.2.0-DEV.272") && (hasfield(::Type{T}, name::Symbol) where T = Base.fieldindex(T, name, false) > 0)

hascolor(io) = VERSION >= v"1.6.0-DEV.481" && get(io, :color, false)
has_escapecodes(s) = occursin(r"\e\[[^m]*m", s)
strip_escapecodes(s) = replace(s, r"\e\[[^m]*m" => "")

# Callable object for testing
struct Foo
    x
end
(foo::Foo)() = println(foo.x)


# Non-standard capture_buffer for testing
struct _TruncatedBuffer
    max_bytes::Int64
    buffer::IOBuffer
    _TruncatedBuffer(max_bytes) = new(max_bytes, IOBuffer())
end

function Base.write(b::_TruncatedBuffer, bytes)
    for byte in bytes
        (b.buffer.size < b.max_bytes) && write(b.buffer, byte)
    end
end

function Base.take!(b::_TruncatedBuffer)
    bytes = take!(b.buffer)
    if length(bytes) == b.max_bytes
        append!(bytes, Vector{UInt8}("…"))
    end
    return bytes
end


@testset "IOCapture.jl" begin
    # Capturing standard output
    c = IOCapture.capture() do
        println("test")
    end
    @test !c.error
    @test c.output == "test\n"
    @test c.value === nothing
    @test c.backtrace isa Vector
    @test isempty(c.backtrace)

    # Capturing standard error
    c = IOCapture.capture() do
        println(stderr, "test")
    end
    @test !c.error
    @test c.output == "test\n"
    @test c.value === nothing
    @test c.backtrace isa Vector
    @test isempty(c.backtrace)

    # Return values
    c = IOCapture.capture() do
        println("test")
        return 42
    end
    @test !c.error
    @test c.output == "test\n"
    @test c.value === 42
    @test c.backtrace isa Vector
    @test isempty(c.backtrace)

    c = IOCapture.capture() do
        println("test")
        println(stderr, "test")
        return rand(5,5)
    end
    @test !c.error
    @test c.output == "test\ntest\n"
    @test c.value isa Matrix{Float64}
    @test c.backtrace isa Vector
    @test isempty(c.backtrace)

    # Callable objects
    c = IOCapture.capture(Foo("callable test"))
    @test !c.error
    @test c.output == "callable test\n"
    @test c.value === nothing

    # Colors get discarded
    c = IOCapture.capture() do
        printstyled("foo", color=:red)
    end
    @test !c.error
    @test c.output == "foo"
    @test c.value === nothing

    # Colors are preserved if it's supported
    c = IOCapture.capture(color=true) do
        printstyled("foo", color=:red)
    end
    @test !c.error
    if hascolor(stdout)
        @test c.output == "\e[31mfoo\e[39m"
    else
        @test c.output == "foo"
    end
    @test c.value === nothing

    # This test checks that deprecation warnings are captured correctly
    c = IOCapture.capture(color=true) do
        println("println")
        @info "@info"
        f() = (Base.depwarn("depwarn", :f); nothing)
        f()
    end
    @test !c.error
    @test c.value === nothing
    # The output is dependent on whether the user is running tests with deprecation
    # warnings enabled or not. To figure out whether that is the case or not, we can
    # look at the .depwarn field of the undocumented Base.JLOptions object.
    @test isdefined(Base, :JLOptions)
    @test hasfield(Base.JLOptions, :depwarn)
    if Base.JLOptions().depwarn == 0 # --depwarn=no, default on Julia >= 1.5
        @test has_escapecodes(c.output) === hascolor(stderr)
        @test strip_escapecodes(c.output) == "println\n[ Info: @info\n"
    else # --depwarn=yes
        @test has_escapecodes(c.output) === hascolor(stderr)
        output_nocol = strip_escapecodes(c.output)
        @test startswith(output_nocol, "println\n[ Info: @info\n┌ Warning: depwarn\n")
    end

    # Exceptions -- normally rethrown
    @test_throws ErrorException IOCapture.capture() do
        println("test")
        error("error")
        return 42
    end

    # .. but can be controlled with rethrow
    c = IOCapture.capture(rethrow=Union{}) do
        println("test")
        error("error")
        return 42
    end
    @test c.error
    @test c.output == "test\n"
    @test c.value isa ErrorException
    @test c.value.msg == "error"

    c = IOCapture.capture(rethrow=Union{}) do
        error("error")
        println("test")
        return 42
    end
    @test c.error
    @test c.output == ""
    @test c.value isa ErrorException
    @test c.value.msg == "error"

    # .. including interrupts
    c = IOCapture.capture(rethrow=Union{}) do
        println("test")
        throw(InterruptException())
        return 42
    end
    @test c.error
    @test c.output == "test\n"
    @test c.value isa InterruptException

    # .. or setting rethrow = InterruptException
    @test_throws InterruptException IOCapture.capture(rethrow=InterruptException) do
        println("test")
        throw(InterruptException())
        return 42
    end

    # .. or a union of exception types
    @test_throws DivideError IOCapture.capture(rethrow=Union{DivideError,InterruptException}) do
        println("test")
        div(1, 0)
        return 42
    end
    @test_throws InterruptException IOCapture.capture(rethrow=Union{DivideError,InterruptException}) do
        println("test")
        throw(InterruptException())
        return 42
    end

    # don't throw on errors that don't match rethrow
    c = IOCapture.capture(rethrow=Union{DivideError,InterruptException}) do
        println("test")
        three = "1" + "2"
        return 42
    end
    @test c.error
    @test c.output == "test\n"
    @test c.value isa MethodError

    # Invalid rethrow values
    @test_throws TypeError IOCapture.capture(()->nothing, rethrow=:foo)
    @test_throws TypeError IOCapture.capture(()->nothing, rethrow=42)
    @test_throws TypeError IOCapture.capture(()->nothing, rethrow=true)
    @test_throws TypeError IOCapture.capture(()->nothing, rethrow=false)

    # Make sure that IOCapture does not stall if we are printing _a lot_ of bytes into
    # stdout. X-ref: https://github.com/fredrikekre/Literate.jl/issues/138
    @testset "Buffer filling" begin
        for nrows = 2 .^ (0:20)
            c = IOCapture.capture() do
                for _ in 1:nrows; print("="^80); end
            end
            @test length(c.output) == 80 * nrows
        end
    end

    # Make sure the global rng isn't affected (JuliaLang/julia#41184).
    Random.seed!(1)
    r = rand()
    Random.seed!(1)
    c = IOCapture.capture(() -> rand())
    @test r == c.value

    # Make sure that IOCapture does not stall if we are printing a lot of
    # "method definition overwritten" warnings.
    # X-ref: https://github.com/JuliaDocs/Documenter.jl/issues/2121
    # Note: This test only makes sense when running with `--warn-overwrite=yes`
    # which is the default since
    # https://github.com/JuliaLang/Pkg.jl/commit/e576700254b3bd1bbc0a2be2fad257cd70839162
    @testset "Buffer not being emptied" begin
        c = IOCapture.capture() do
            for i in 1:1024
                eval(:(function TEST_FUNC() 1 end))
            end
        end
        @test true # just make sure we get here
    end

    @testset "passthrough" begin
        mktemp() do logfile, io
            redirect_stdout(io) do
                print("<pre>")
                c = IOCapture.capture(passthrough=true) do
                    for i in 1:128
                        print("HelloWorld")
                    end
                end
                print("<post>")
            end
            close(io)
            @test c.output == "HelloWorld"^128
            @test read(logfile, String) == "<pre>" * "HelloWorld"^128 * "<post>"
        end
        # Interaction of passthrough= with color=
        # Also tests that stdout and stderr get merged in both .output and passthrough
        if VERSION >= v"1.6.0"
            # older versions don't support `redirect_stdout(IOContext…`
            mktemp() do logfile, io
                redirect_stdout(IOContext(io, :color => true)) do
                    c = IOCapture.capture(passthrough=true) do
                        printstyled(stdout, "foo"; color=:blue)
                        printstyled(stderr, "bar"; color=:red)
                    end
                end
                close(io)
                @test c.output == "foobar"
                @test c.output == read(logfile, String)
            end
            mktemp() do logfile, io
                redirect_stdout(IOContext(io, :color => true)) do
                    c = IOCapture.capture(passthrough=true, color=true) do
                        printstyled(stdout, "foo"; color=:blue)
                        printstyled(stderr, "bar"; color=:red)
                    end
                end
                close(io)
                @test c.output == "\e[34mfoo\e[39m\e[31mbar\e[39m"
                @test c.output == read(logfile, String)
            end
        end
    end

    @testset "capture_buffer" begin
        mktemp() do logfile, io
            text = "Hello World (this text has more than 8 bytes)"
            redirect_stdout(io) do
                c = IOCapture.capture(passthrough=true, capture_buffer=_TruncatedBuffer(8)) do
                    print(text)
                end
            end
            close(io)
            @test c.output == "Hello Wo…"
            @test read(logfile, String) == text
        end
    end

    if VERSION >= v"1.6.0-DEV.481"
        @testset "io_context" begin
            # Avoids needing to define this at top-level as a `module M` syntax.
            M = Module(:M)
            Core.eval(M, :(struct T end))

            no_io_context = IOCapture.capture() do
                println(M.T())
            end
            @test rstrip(no_io_context.output) == "Main.M.T()"

            with_io_context = IOCapture.capture(io_context=[:module => M]) do
                println(M.T())
            end
            @test rstrip(with_io_context.output) == "T()"

            @test_throws ArgumentError IOCapture.capture(io_context=["module" => M]) do
                println(M.T())
            end
        end
    end
end
