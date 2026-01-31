import TestItemRunner

# Some test dependencies (e.g., Plots/GR) require newer Julia versions and
# won't compile on older ones. Tag such tests with :juliaXY (e.g., :julia110)
# and add the minimum version here. The filter skips tests whose required
# version exceeds the current Julia version.
const VERSION_TAGS = Dict(:julia110 => v"1.10")

function should_run(ti)
    for tag in ti.tags
        min_ver = get(VERSION_TAGS, tag, nothing)
        min_ver !== nothing && VERSION < min_ver && return false
    end
    return true
end

TestItemRunner.@run_package_tests filter = should_run
