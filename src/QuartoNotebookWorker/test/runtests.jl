import TestItemRunner

# Some test dependencies (e.g., Plots/GR) require newer Julia versions and
# won't compile on older ones. Tag such tests with :juliaXY (e.g., :julia110)
# and add the minimum version here. The filter skips tests whose required
# version exceeds the current Julia version.
#
# Some packages are conditionally removed by CI on certain platforms (e.g.,
# RCall on Windows + Julia 1.12+ due to temp cleanup hangs). Tests tagged
# with the package name are skipped when the package isn't available.
const RCALL_AVAILABLE = !isnothing(Base.find_package("RCall"))

function should_run(ti)
    version_tags = (julia110 = v"1.10",)
    for tag in ti.tags
        min_ver = get(version_tags, tag, nothing)
        min_ver !== nothing && VERSION < min_ver && return false
    end
    if :rcall in ti.tags && !RCALL_AVAILABLE
        return false
    end
    return true
end

TestItemRunner.@run_package_tests filter = should_run
