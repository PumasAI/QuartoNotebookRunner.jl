module QuartoNotebookWorker

module Packages

import TOML

is_precompiling() = ccall(:jl_generating_output, Cint, ()) == 1

const packages = let
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    uuid = Base.UUID(project["uuid"])
    key = "packages"
    is_precompiling() && Base.record_compiletime_preference(uuid, key)
    Base.get_preferences(uuid)[key]
end

for package in packages
    include(package)
end

end

# Handle older versions of Julia that don't have support for package extensions.
# Note that this macro must be called in the root-module of a package, otherwise
# `pathof(__module__)` will be `nothing`.
import .Packages.PackageExtensionCompat: @require_extensions
function __init__()
    @require_extensions
end

# Includes.

include("package_hooks.jl")
include("InlineDisplay.jl")
include("NotebookState.jl")
include("NotebookInclude.jl")
include("refresh.jl")
include("render.jl")
include("utilities.jl")
include("ojs_define.jl")

end
