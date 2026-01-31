include("utilities/project_precompile.jl")

import TestItemRunner

# Filter test items: skip worker tests (they have their own test project) and
# tests requiring newer Julia versions than currently running.
function should_run(ti)
    # Exclude QuartoNotebookWorker tests - they run separately with their own Project.toml
    contains(ti.filename, "QuartoNotebookWorker") && return false

    # Version-gated tests: tag with :juliaXY to require minimum Julia version
    version_tags = (julia110 = v"1.10",)
    for tag in ti.tags
        min_ver = get(version_tags, tag, nothing)
        min_ver !== nothing && VERSION < min_ver && return false
    end
    return true
end

TestItemRunner.@run_package_tests filter = should_run
