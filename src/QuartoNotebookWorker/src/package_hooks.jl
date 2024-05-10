# Package loading/refresh hooks.

let hooks = Set{Function}()
    global function run_package_loading_hooks()
        for hook in hooks
            Base.@invokelatest hook()
        end
    end
    global function add_package_loading_hook!(f::Function)
        push!(hooks, f)
    end
end

let hooks = Set{Function}()
    global function run_package_refresh_hooks()
        for hook in hooks
            Base.@invokelatest hook()
        end
    end
    global function add_package_refresh_hook!(f::Function)
        push!(hooks, f)
    end
end


# Post eval/error hooks.

let hooks = Set{Function}()
    global function run_post_eval_hooks()
        for hook in hooks
            Base.@invokelatest hook()
        end
    end
    global function add_post_eval_hook!(f::Function)
        push!(hooks, f)
    end
end

let hooks = Set{Function}()
    global function run_post_error_hooks()
        for hook in hooks
            Base.@invokelatest hook()
        end
    end
    global function add_post_error_hook!(f::Function)
        push!(hooks, f)
    end
end
