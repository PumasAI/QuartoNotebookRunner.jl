# Minimal PrecompileTools for Julia 1.6+
# Based on PrecompileTools.jl v1.2.1 and v1.3.3

module PrecompileToolsLite

export @setup_workload, @compile_workload

# Version detection
const have_native_tagging = VERSION >= v"1.12.0-DEV" && isdefined(Base, :generating_output)
const have_force_compile =
    isdefined(Base, :Experimental) &&
    isdefined(Base.Experimental, Symbol("#@force_compile"))
const have_inference_tracking = isdefined(Core.Compiler, :__set_measure_typeinf)

# Julia 1.12+ native approach
@static if have_native_tagging
    @noinline is_generating_output() = ccall(:jl_generating_output, Cint, ()) == 1

    macro latestworld_if_toplevel()
        Expr(Symbol("latestworld-if-toplevel"))
    end

    function tag_newly_inferred_enable()
        ccall(:jl_tag_newly_inferred_enable, Cvoid, ())
    end

    function tag_newly_inferred_disable()
        ccall(:jl_tag_newly_inferred_disable, Cvoid, ())
    end

    macro compile_workload(ex::Expr)
        iscompiling = :($PrecompileToolsLite.is_generating_output())
        ex = quote
            begin
                $PrecompileToolsLite.@latestworld_if_toplevel
                $(esc(ex))
            end
        end
        ex = quote
            $PrecompileToolsLite.tag_newly_inferred_enable()
            try
                $ex
            finally
                $PrecompileToolsLite.tag_newly_inferred_disable()
            end
        end
        return quote
            if $iscompiling
                $ex
            end
        end
    end

    macro setup_workload(ex::Expr)
        iscompiling = :(ccall(:jl_generating_output, Cint, ()) == 1)
        return quote
            if $iscompiling
                let
                    $PrecompileToolsLite.@latestworld_if_toplevel
                    $(esc(ex))
                end
            end
        end
    end

    # Julia 1.6-1.11 fallback approach
else
    function precompile_mi(mi)
        precompile(mi.specTypes)
        return
    end

    function check_edges(node)
        parentmi = node.mi_info.mi
        for child in node.children
            childmi = child.mi_info.mi
            if !(isdefined(childmi, :backedges) && parentmi ∈ childmi.backedges)
                precompile_mi(childmi)
            end
            check_edges(child)
        end
    end

    function precompile_roots(roots)
        for child in roots
            precompile_mi(child.mi_info.mi)
            check_edges(child)
        end
    end

    macro compile_workload(ex::Expr)
        iscompiling = :(ccall(:jl_generating_output, Cint, ()) == 1)

        # Force compilation
        if have_force_compile
            ex = quote
                begin
                    Base.Experimental.@force_compile
                    $(esc(ex))
                end
            end
        else
            ex = quote
                while false
                end
                $(esc(ex))
            end
        end

        # Optional inference tracking (Julia 1.8+)
        if have_inference_tracking
            ex = quote
                Core.Compiler.Timings.reset_timings()
                Core.Compiler.__set_measure_typeinf(true)
                try
                    $ex
                finally
                    Core.Compiler.__set_measure_typeinf(false)
                    Core.Compiler.Timings.close_current_timer()
                end
                $PrecompileToolsLite.precompile_roots(
                    Core.Compiler.Timings._timings[1].children,
                )
            end
        end

        return quote
            if $iscompiling
                $ex
            end
        end
    end

    macro setup_workload(ex::Expr)
        iscompiling = :(ccall(:jl_generating_output, Cint, ()) == 1)
        return quote
            if $iscompiling
                $(esc(ex))
            end
        end
    end
end

end # module PrecompileToolsLite
