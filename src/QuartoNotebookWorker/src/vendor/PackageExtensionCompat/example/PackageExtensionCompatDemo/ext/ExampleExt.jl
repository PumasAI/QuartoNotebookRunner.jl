# This module is loaded when both PackageExtensionCompatDemo and Example are loaded,
# as declared in the [extensions] section of Project.toml.
module ExampleExt

using PackageExtensionCompatDemo, Example

# This extends the `hello_world` function with a new method.
# So after the extension is loaded, you can call `hello_world()`.
PackageExtensionCompatDemo.hello_world() = Example.hello("World")

# You can optionally also define an __init__ function which is called when the extension
# is loaded. In this case it just prints a message to the terminal.
function __init__()
    @info "HELLO!!!"
end

end
