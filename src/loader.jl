let file = "$(@__FILE__).$VERSION.jls",
    pkgid = Base.PkgId(Base.UUID("9e88b42a-f829-5b0c-bbe9-9e923198166b"), "Serialization"),
    Serialization = Base.require(pkgid)

    Base.include_dependency(file)
    cd(@__DIR__) do
        function _walk!(f, ex::Expr)
            for (nth, x) in enumerate(ex.args)
                ex.args[nth] = _walk!(f, x)
            end
            return ex
        end
        _walk!(f, other) = f(other)

        _fix_file(x::LineNumberNode) = LineNumberNode(x.line, Symbol(@__FILE__))
        _fix_file(other) = other

        expr = Serialization.deserialize(file)
        _walk!(_fix_file, expr)

        for ex in expr.args
            Core.eval(@__MODULE__, ex)
        end
    end
end
