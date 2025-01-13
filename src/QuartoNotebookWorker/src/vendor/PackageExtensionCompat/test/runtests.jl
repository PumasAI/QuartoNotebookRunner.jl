using Test, Pkg, Random, UUIDs, PackageExtensionCompat

function make_package(dir; name=nothing, uuid=nothing, src="", deps=[], weakdeps=[], extensions=[], includes=[])
    if name === nothing
        name = "TestPackage_$(randstring())"
    end
    if uuid === nothing
        uuid = string(uuid4())
    end
    rootpath = joinpath(dir, name)
    mkpath(rootpath)
    open(joinpath(rootpath, "Project.toml"), "w") do io
        println(io, "name = $(repr(name))")
        println(io, "uuid = $(repr(uuid))")
        println(io, "[deps]")
        for dep in deps
            println(io, "$(dep.name) = $(repr(dep.uuid))")
        end
        println(io, "[weakdeps]")
        for dep in weakdeps
            println(io, "$(dep.name) = $(repr(dep.uuid))")
        end
        println(io, "[extensions]")
        for ext in extensions
            println(io, "$(ext.name) = [$(join(map(repr, ext.deps), ", "))]")
        end
    end
    srcpath = joinpath(rootpath, "src")
    mkpath(srcpath)
    open(joinpath(srcpath, "$name.jl"), "w") do io
        print(io, """
        module $name
        $src
        end
        """)
    end
    extpath = joinpath(rootpath, "ext")
    mkpath(extpath)
    for ext in [extensions; includes]
        open(joinpath(extpath, "$(ext.name).jl"), "w") do io
            print(io, """
            module $(ext.name)
            $(replace(ext.src, "PKGNAME" => name))
            end
            """)
        end
    end
    (name=name, uuid=uuid, path=rootpath)
end

function test_extension(; dir, slug, extsrc, incsrc = nothing)
    # a secret value embedded into the extension which can only be recovered if the
    # extension is loaded correctly
    secret = rand(Int)
    # an empty package, which exists just to trigger loading of an extension
    pkg1 = make_package(dir;
        name = "PackageExtensionCompat_Test_$(slug)_Trigger",
        src = """
        const SECRET = $secret
        """
    )
    # a package with an extension depending on the previous package
    pkg2 = make_package(dir;
        name = "PackageExtensionCompat_Test_$(slug)_Main",
        deps = [
            (name="PackageExtensionCompat", uuid="65ce6f38-6b18-4e1d-a461-8949797d7930"),
        ],
        src = """
        using PackageExtensionCompat
        function __init__()
            @require_extensions
        end
        function secret end
        """,
        weakdeps = [pkg1],
        extensions = [
            (
                name = "TestExt",
                deps = [pkg1.name],
                src = replace(replace(extsrc, "PKG1NAME" => pkg1.name), "PKG2NAME" => "PKGNAME"),
            )
        ],
        includes = incsrc === nothing ? [] : [
            (
                name = "TestExtSub",
                src = replace(replace(incsrc, "PKG1NAME" => pkg1.name), "PKG2NAME" => "PKGNAME"),
            )
        ]
    )
    # add these packages to the project
    Pkg.develop([
        Pkg.PackageSpec(path=pkg1.path),
        Pkg.PackageSpec(path=pkg2.path),
    ])
    # load the second package and test that the extension is not loaded
    m2 = Base.require(Base.PkgId(UUID(pkg2.uuid), pkg2.name))
    @test length(methods(m2.secret)) == 0
    # load the first package and test that the extension is loaded
    m1 = Base.require(Base.PkgId(UUID(pkg1.uuid), pkg1.name))
    @test length(methods(m2.secret)) == 1
    @test Base.invokelatest(m2.secret) === secret
    # remove these packages
    Pkg.rm([
        Pkg.PackageSpec(name=pkg1.name),
        Pkg.PackageSpec(name=pkg2.name),
    ])
end

@testset "PackageExtensionCompat" begin

    mktempdir() do dir

        @testset "using" begin
            test_extension(
                dir = dir,
                slug = "1",
                extsrc = """
                using PKG2NAME, PKG1NAME
                PKG2NAME.secret() = PKG1NAME.SECRET
                """
            )
        end

        @testset "using-get" begin
            if Base.VERSION ≥ v"1.6"
                test_extension(
                    dir = dir,
                    slug = "2",
                    extsrc = """
                    using PKG2NAME
                    using PKG1NAME: SECRET as THE_SECRET
                    PKG2NAME.secret() = THE_SECRET
                    """
                )
            else
                test_extension(
                    dir = dir,
                    slug = "2",
                    extsrc = """
                    using PKG2NAME
                    using PKG1NAME: SECRET
                    const THE_SECRET = SECRET
                    PKG2NAME.secret() = THE_SECRET
                    """
                )
            end
        end

        @testset "import" begin
            test_extension(
                dir = dir,
                slug = "3",
                extsrc = """
                using PKG2NAME
                import PKG1NAME
                PKG2NAME.secret() = PKG1NAME.SECRET
                """
            )
        end

        @testset "import-as" begin
            if Base.VERSION ≥ v"1.6"
                test_extension(
                    dir = dir,
                    slug = "4",
                    extsrc = """
                    using PKG2NAME
                    import PKG1NAME as FOO
                    PKG2NAME.secret() = FOO.SECRET
                    """
                )
            end
        end

        @testset "nested-using" begin
            test_extension(
                dir = dir,
                slug = "5",
                extsrc = """
                using PKG2NAME
                @static if 1 < 2
                    if 3 < 4
                        using PKG1NAME
                    end
                end
                PKG2NAME.secret() = PKG1NAME.SECRET
                """
            )
        end

        @testset "__init__" begin
            test_extension(
                dir = dir,
                slug = "6",
                extsrc = """
                using PKG2NAME, PKG1NAME
                const SECRET = Ref{Union{Nothing,Int}}(nothing)
                function __init__()
                    SECRET[] = PKG1NAME.SECRET
                end
                PKG2NAME.secret() = SECRET[]::Int
                """
            )
        end

        @testset "anonymous-functions" begin
            test_extension(
                dir = dir,
                slug = "7",
                extsrc = """
                using PKG2NAME, PKG1NAME
                PKG2NAME.secret() = PKG1NAME.SECRET
                f = (x...) -> (x, x)
                """
            )
        end

        @testset "eval-interpolate-function-name" begin
            test_extension(
                dir = dir,
                slug = "8",
                extsrc = """
                using PKG2NAME, PKG1NAME
                funcname = :secret
                @eval function PKG2NAME.\$(funcname)()
                    PKG1NAME.SECRET
                end
                """
            )
        end

        @testset "submodule" begin
            test_extension(
                dir = dir,
                slug = "9",
                extsrc = """
                module SubMod
                using PKG2NAME, PKG1NAME
                PKG2NAME.secret() = PKG1NAME.SECRET
                end
                """
            )
        end

        @testset "inner-include" begin
            test_extension(
                dir = dir,
                slug = "10",
                extsrc = """
                include("TestExtSub.jl")
                @assert TestExtSub isa Module
                """,
                incsrc = """
                using PKG2NAME, PKG1NAME
                PKG2NAME.secret() = PKG1NAME.SECRET
                """
            )
        end
    end

end
