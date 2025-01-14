# Used to copy vendored versions of the below packages into the worker package
# source rather than requiring them as dependencies.

import IOCapture
import PackageExtensionCompat
import Requires

for each in [IOCapture, PackageExtensionCompat, Requires]
    dir = Base.pkgdir(each)
    for (root, dirs, files) in walkdir(dir)
        for file in files
            src = joinpath(root, file)
            path = normpath(joinpath(relpath(root, dir), file))
            dst = joinpath(@__DIR__, String(nameof(each)), path)
            content = read(src, String)
            mkpath(dirname(dst))
            write(dst, content)
        end
    end
end
