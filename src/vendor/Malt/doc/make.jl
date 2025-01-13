using Documenter
using Malt

makedocs(
    sitename = "Malt",
    format = Documenter.HTML(),
    modules = [Malt],
    warnonly = [:missing_docs],
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/JuliaPluto/Malt.jl.git"
)
