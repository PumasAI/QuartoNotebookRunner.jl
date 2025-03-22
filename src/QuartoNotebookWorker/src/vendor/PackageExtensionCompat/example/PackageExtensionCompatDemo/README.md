# PackageExtensionCompatDemo

This is a minimal example of using Julia's extension packages and using
PackageExtensionCompat.jl to make these backwards-compatible.

The package exports a function `hello_world()` which only works if `Example` is also loaded.
It calls the `Example.hello` function.

Read the comments in the other files in this package for more information.

## Usage

Clone this repository (or otherwise copy the PackageExtensionCompatDemo folder) and install
the package like this:

```julia
using Pkg
Pkg.develop("/path/to/PackageExtensionCompatDemo")
Pkg.add("Example")
```

If you try to call `hello_world` from the demo package, it will error:

```julia
using PackageExtensionCompatDemo
hello_world()  # ERROR: ...
```

But if you also load `Example` then it will succeed
```julia
using Example
hello_world()   # "Hello, World"
```
