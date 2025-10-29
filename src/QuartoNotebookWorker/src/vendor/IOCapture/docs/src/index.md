# IOCapture

[![Version](https://juliahub.com/docs/IOCapture/version.svg)](https://juliahub.com/ui/Packages/IOCapture/shLGd)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliadocs.github.io/IOCapture.jl/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliadocs.github.io/IOCapture.jl/dev)
[![CI](https://github.com/JuliaDocs/IOCapture.jl/workflows/CI/badge.svg)](https://github.com/JuliaDocs/IOCapture.jl/actions)
[![Coverage](https://codecov.io/gh/JuliaDocs/IOCapture.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaDocs/IOCapture.jl)

Provides the `IOCapture.capture(f)` function which evaluates the function `f`, captures the
standard output and standard error, and returns it as a string, together with the return
value. For example:

```julia-repl
julia> c = IOCapture.capture() do
           println("test")
           return 42
       end;

julia> c.value, c.output
(42, "test\n")
```

See the docstring for full documentation.

## Known limitations

### Separately stored `stdout` or `stderr` objects

The capturing does not work properly if `f` prints to the `stdout` object that has been
stored in a separate variable or object, e.g.:

```julia-repl
julia> const original_stdout = stdout;

julia> c = IOCapture.capture() do
           println("output to stdout")
           println(original_stdout, "output to original stdout")
       end;
output to original stdout

julia> c.output
"output to stdout\n"
```

Relatedly, it is possible to run into errors if the `stdout` or `stderr` objects from
within a `capture` are being used in a subsequent `capture` or outside of the capture:

```julia-repl
julia> c = IOCapture.capture() do
           return stdout
       end;

julia> println(c.value, "test")
ERROR: IOError: stream is closed or unusable
Stacktrace:
 [1] check_open at ./stream.jl:328 [inlined]
 [2] uv_write_async(::Base.PipeEndpoint, ::Ptr{UInt8}, ::UInt64) at ./stream.jl:959
 ...
```

This is because `stdout` and `stderr` within an `capture` actually refer to the temporary
redirect streams which get cleaned up at the end of the `capture` call.

### ANSI color / escape sequences

On Julia 1.5 and earlier, setting `color` to `true` has no effect, because the [ability to
set `IOContext` attributes on redirected streams was added in
1.6](https://github.com/JuliaLang/julia/pull/36688). I.e. on those older Julia versions the
captured output will generally not contain ANSI color escape sequences.


## Similar packages

* [Suppressor.jl](https://github.com/JuliaIO/Suppressor.jl) provides similar functionality,
  but with a macro-based interface.
