@testitem "hooks catch errors and continue" begin
    import QuartoNotebookWorker as QNW

    # Track which hooks ran
    ran = Ref{Vector{Symbol}}(Symbol[])

    # Hooks run in undefined order (Set), so we just track they all ran
    hooks = Set{Function}()

    function good_hook_1()
        push!(ran[], :good1)
    end
    function bad_hook()
        push!(ran[], :bad)
        error("intentional hook failure")
    end
    function good_hook_2()
        push!(ran[], :good2)
    end

    push!(hooks, good_hook_1)
    push!(hooks, bad_hook)
    push!(hooks, good_hook_2)

    # Should not throw, should warn
    @test_logs (:warn, r"Error in test hook") QNW._run_hooks(hooks, "test")

    # All hooks should have run despite one failing
    @test :good1 in ran[]
    @test :bad in ran[]
    @test :good2 in ran[]
    @test length(ran[]) == 3
end

@testitem "hooks work with empty set" begin
    import QuartoNotebookWorker as QNW

    # Should not throw on empty hooks
    QNW._run_hooks(Set{Function}(), "empty")
end
