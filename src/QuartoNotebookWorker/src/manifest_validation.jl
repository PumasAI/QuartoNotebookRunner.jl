function _manifest_in_sync()
    # Versions before Julia 1.8 do not have access to this function, so we skip
    # the check for them.
    @static if isdefined(Pkg.Operations, :is_manifest_current)
        project = Base.active_project()
        if isfile(project)
            env_cache = Pkg.Types.EnvCache(project)
            if Pkg.Operations.is_manifest_current(env_cache) === false
                manifest = Base.project_file_manifest_path(project)
                message = """
                The notebook environment is out-of-sync.

                project_toml = $(repr(project))
                manifest_toml = $(repr(manifest))

                Run `Pkg.resolve()` for this environment to ensure the manifest file
                is consistent with the project file and then rerun this notebook.
                """
                return message
            end
        end
    end
    return nothing
end
