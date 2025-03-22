module PackageExtensionCompatDemo

# This is the minimal set-up to make extensions backwards-compatible.
# On older versions of Julia, `@require_extensions` expands to multiple `Requires.@require` calls.
# On newer versions of Julia, it does nothing.
# If you skip this, then extensions will not be loaded on Julia 1.8 and earlier.
using PackageExtensionCompat
function __init__()
    @require_extensions
end

# The package exports a function called hello_world.
# Initially it has no methods, so calling it will always throw an error.
export hello_world
function hello_world end

end # module PackageExtensionCompatDemo
