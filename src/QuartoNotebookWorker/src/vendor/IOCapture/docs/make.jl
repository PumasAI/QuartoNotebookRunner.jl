using Documenter
using IOCapture

DocMeta.setdocmeta!(IOCapture, :DocTestSetup, :(using IOCapture); recursive = true)

makedocs(
    sitename = "IOCapture.jl",
    modules = [IOCapture],
    clean = false,
    pages = Any[
        "Readme" => "index.md",
        "Docstrings" => "autodocs.md",
    ],
    format = Documenter.HTML(),
)

deploydocs(
    repo = "github.com/JuliaDocs/IOCapture.jl.git",
)
