# Package loading/refresh hooks.

function _run_hooks(hooks, hook_type::String)
    for hook in hooks
        try
            Base.@invokelatest hook()
        catch e
            @warn "Error in $hook_type hook" hook exception = (e, catch_backtrace())
        end
    end
end

let hooks = Set{Function}()
    global function run_package_loading_hooks()
        _run_hooks(hooks, "package loading")
    end
    global function add_package_loading_hook!(f::Function)
        push!(hooks, f)
    end
end

let hooks = Set{Function}()
    global function run_package_refresh_hooks()
        _run_hooks(hooks, "package refresh")
    end
    global function add_package_refresh_hook!(f::Function)
        push!(hooks, f)
    end
end


# Post eval/error hooks.

let hooks = Set{Function}()
    global function run_post_eval_hooks()
        _run_hooks(hooks, "post eval")
    end
    global function add_post_eval_hook!(f::Function)
        push!(hooks, f)
    end
end

let hooks = Set{Function}()
    global function run_post_error_hooks()
        _run_hooks(hooks, "post error")
    end
    global function add_post_error_hook!(f::Function)
        push!(hooks, f)
    end
end
