@testitem "with_context sets and clears context" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    # Outside context returns nothing
    @test NS.current_context() === nothing

    mod = NS.define_notebook_module!()
    ctx = NS.NotebookContext(
        "test.qmd",
        "/project",
        Dict{String,Any}("a" => 1),
        mod,
        "/cwd",
        String[],
    )

    NS.with_context(ctx) do
        @test NS.current_context() === ctx
        @test NS.current_context().file == "test.qmd"
        @test NS.current_context().options["a"] == 1
    end

    # After block, context cleared
    @test NS.current_context() === nothing
end

@testitem "with_cell_options sets and clears options" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    # Outside returns empty dict
    @test NS.current_cell_options() == Dict{String,Any}()

    opts = Dict{String,Any}("echo" => false, "eval" => true)
    NS.with_cell_options(opts) do
        @test NS.current_cell_options() === opts
        @test NS.current_cell_options()["echo"] == false
    end

    @test NS.current_cell_options() == Dict{String,Any}()
end

@testitem "notebook_module returns ctx.mod when in context" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    mod = NS.define_notebook_module!()
    ctx = NS.NotebookContext("", "", Dict{String,Any}(), mod, pwd(), String[])

    NS.with_context(ctx) do
        @test NS.notebook_module() === mod
    end
end

@testitem "notebook_module returns nothing when no context" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    @test NS.notebook_module() === nothing
end

@testitem "with_env_vars sets and restores variables" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    # Ensure clean state
    delete!(ENV, "QNW_TEST_VAR")

    NS.with_env_vars(["QNW_TEST_VAR=hello"]) do
        @test ENV["QNW_TEST_VAR"] == "hello"
    end

    @test !haskey(ENV, "QNW_TEST_VAR")
end

@testitem "with_env_vars restores original value" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    ENV["QNW_TEST_VAR"] = "original"

    NS.with_env_vars(["QNW_TEST_VAR=modified"]) do
        @test ENV["QNW_TEST_VAR"] == "modified"
    end

    @test ENV["QNW_TEST_VAR"] == "original"
    delete!(ENV, "QNW_TEST_VAR")
end

@testitem "with_env_vars handles empty list" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    result = NS.with_env_vars(String[]) do
        42
    end
    @test result == 42
end

@testitem "with_env_vars restores on exception" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    delete!(ENV, "QNW_TEST_VAR")

    try
        NS.with_env_vars(["QNW_TEST_VAR=temp"]) do
            @test ENV["QNW_TEST_VAR"] == "temp"
            error("intentional")
        end
    catch
    end

    @test !haskey(ENV, "QNW_TEST_VAR")
end

@testitem "render_mimetypes 2-arg errors without context" begin
    import QuartoNotebookWorker as QNW

    # Call 2-arg version without notebook context
    @test_throws ErrorException QNW.render_mimetypes("value", Dict{String,Any}())
end

@testitem "nested contexts are independent" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    mod1 = NS.define_notebook_module!()
    mod2 = NS.define_notebook_module!()
    ctx1 = NS.NotebookContext("file1.qmd", "", Dict{String,Any}(), mod1, pwd(), String[])
    ctx2 = NS.NotebookContext("file2.qmd", "", Dict{String,Any}(), mod2, pwd(), String[])

    NS.with_context(ctx1) do
        @test NS.current_context().file == "file1.qmd"

        NS.with_context(ctx2) do
            @test NS.current_context().file == "file2.qmd"
        end

        # Outer context restored
        @test NS.current_context().file == "file1.qmd"
    end
end

@testitem "with_test_context sets up complete context" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    NS.with_test_context() do
        @test NS.current_context() !== nothing
        @test NS.notebook_module() !== nothing
        @test NS.current_cell_options() == Dict{String,Any}()
    end
end

@testitem "with_test_context accepts custom options" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    opts = Dict{String,Any}("format" => Dict("pandoc" => Dict("to" => "html")))
    NS.with_test_context(; options = opts) do
        @test NS.current_context().options == opts
    end
end

@testitem "package hooks see current_context inside with_context" begin
    import QuartoNotebookWorker as QNW
    NS = QNW.NotebookState

    observed_options = Ref{Any}(nothing)
    hook = () -> begin
        ctx = NS.current_context()
        observed_options[] = ctx === nothing ? nothing : ctx.options
    end
    QNW.add_package_refresh_hook!(hook)
    try
        opts = Dict{String,Any}("fig-width" => 7)
        mod = NS.define_notebook_module!()
        ctx = NS.NotebookContext("hook_test.qmd", "", opts, mod, pwd(), String[])

        NS.with_context(ctx) do
            QNW.run_package_refresh_hooks()
        end

        @test observed_options[] === opts
    finally
        QNW.delete_package_refresh_hook!(hook)
    end
end
