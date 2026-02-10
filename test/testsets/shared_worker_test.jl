@testitem "Shared worker process" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    function write_qmd(dir, name; share = true, exeflags = nothing, code = "1 + 1")
        path = joinpath(dir, name)
        lines = String["---"]
        if share || exeflags !== nothing
            push!(lines, "julia:")
            share && push!(lines, "  share_worker_process: true")
            exeflags !== nothing && push!(lines, "  exeflags: [\"$exeflags\"]")
        end
        push!(lines, "---")
        push!(lines, "")
        push!(lines, "```{julia}")
        push!(lines, code)
        push!(lines, "```")
        write(path, join(lines, "\n"))
        return path
    end

    @testset "same config shares worker" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                # Both files tracked separately
                @test length(s.workers) == 2
                # But share one worker process
                @test s.workers[abspath(a)].worker === s.workers[abspath(b)].worker
                @test length(s.shared_workers) == 1
                entry = first(values(s.shared_workers))
                @test Set([abspath(a), abspath(b)]) == entry.users
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "different exeflags get separate workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; exeflags = "--check-bounds=yes")
            b = write_qmd(dir, "b.qmd"; exeflags = "--check-bounds=no")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                @test length(s.workers) == 2
                @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
                @test length(s.shared_workers) == 2
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "default (no share) creates separate workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; share = false)
            b = write_qmd(dir, "b.qmd"; share = false)
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                @test length(s.workers) == 2
                @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
                @test isempty(s.shared_workers)
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "mixed shared and non-shared stay separate" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; share = true)
            b = write_qmd(dir, "b.qmd"; share = false)
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                @test length(s.workers) == 2
                @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
                @test length(s.shared_workers) == 1
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "close one shared notebook, worker survives for other" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                pid = s.workers[abspath(a)].worker.proc_pid

                QNR.close!(s, abspath(a))
                @test length(s.workers) == 1
                @test !haskey(s.workers, abspath(a))
                # Shared worker still alive
                @test length(s.shared_workers) == 1
                entry = first(values(s.shared_workers))
                @test entry.worker.proc_pid == pid
                @test entry.users == Set([abspath(b)])

                # Close last user, worker stops
                QNR.close!(s, abspath(b))
                @test isempty(s.workers)
                @test isempty(s.shared_workers)
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "close!(server) cleans up shared workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                @test length(s.shared_workers) == 1
            finally
                QNR.close!(s)
            end
            @test isempty(s.workers)
            @test isempty(s.shared_workers)
        end
    end

    @testset "shared notebooks have isolated evaluation contexts" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "x = 42")
            b = write_qmd(dir, "b.qmd"; code = "#| error: true\nx")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                result = QNR.run!(s, b)
                @test s.workers[abspath(a)].worker === s.workers[abspath(b)].worker
                # B's cell should have an UndefVarError — x from A is not visible
                output = result.cells[2].outputs[1]
                @test output.output_type == "error"
                @test output.ename == "UndefVarError"
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "close! succeeds when worker is dead" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)

                # Kill the shared worker process directly
                file_a = s.workers[abspath(a)]
                Base.kill(file_a.worker.proc, Base.SIGKILL)
                while QNR.WorkerIPC.isrunning(file_a.worker)
                    sleep(0.01)
                end

                # close! should still complete host-side cleanup
                @test QNR.close!(s, abspath(a)) == true
                @test !haskey(s.workers, abspath(a))
                @test length(s.shared_workers) == 1
                entry = first(values(s.shared_workers))
                @test entry.users == Set([abspath(b)])

                # Close last user
                @test QNR.close!(s, abspath(b)) == true
                @test isempty(s.workers)
                @test isempty(s.shared_workers)
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "forceclose! cleans up sibling files" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "sleep(30)")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                # Run B first (completes, stays in workers due to daemon timeout)
                QNR.run!(s, b)
                @test haskey(s.workers, abspath(b))

                # Spawn A in background (holds file lock during sleep)
                run_task = Threads.@spawn try
                    QNR.run!(s, a)
                catch e
                    e
                end

                # Wait for A's file lock to be held
                while true
                    file = lock(s.lock) do
                        get(s.workers, abspath(a), nothing)
                    end
                    file !== nothing && islocked(file.lock) && break
                    sleep(0.01)
                end

                # Force-close A — should also remove sibling B
                QNR.forceclose!(s, abspath(a))

                @test isempty(s.workers)
                @test isempty(s.shared_workers)

                # Background task should error with force-close message
                result = fetch(run_task)
                @test result isa Exception
                @test contains(sprint(showerror, result), "force-closed")
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "re-render shared notebook works" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "x = 42")
            b = write_qmd(dir, "b.qmd"; code = "y = 99")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                pid = s.workers[abspath(a)].worker.proc_pid

                # Re-render a — refresh! should work without restarting worker
                QNR.run!(s, a)
                @test s.workers[abspath(a)].worker.proc_pid == pid
                @test length(s.shared_workers) == 1
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "re-render after closing sibling" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "1 + 1")
            b = write_qmd(dir, "b.qmd"; code = "2 + 2")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                pid = s.workers[abspath(a)].worker.proc_pid

                QNR.close!(s, abspath(a))
                @test !haskey(s.workers, abspath(a))

                # B still works on the same worker
                QNR.run!(s, b)
                @test s.workers[abspath(b)].worker.proc_pid == pid
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "forceclose! gives mid-run sibling clean error" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "sleep(30)")
            b = write_qmd(dir, "b.qmd"; code = "sleep(30)")
            s = QNR.Server()
            try
                # Spawn both in background
                task_a = Threads.@spawn try
                    QNR.run!(s, a)
                catch e
                    e
                end
                # Wait for A's lock
                while true
                    file = lock(s.lock) do
                        get(s.workers, abspath(a), nothing)
                    end
                    file !== nothing && islocked(file.lock) && break
                    sleep(0.01)
                end

                task_b = Threads.@spawn try
                    QNR.run!(s, b)
                catch e
                    e
                end
                # Wait for B's lock
                while true
                    file = lock(s.lock) do
                        get(s.workers, abspath(b), nothing)
                    end
                    file !== nothing && islocked(file.lock) && break
                    sleep(0.01)
                end

                QNR.forceclose!(s, abspath(a))

                result_a = fetch(task_a)
                result_b = fetch(task_b)
                @test result_a isa Exception
                @test result_b isa Exception
                @test contains(sprint(showerror, result_a), "force-closed")
                @test contains(sprint(showerror, result_b), "force-closed")

                @test isempty(s.workers)
                @test isempty(s.shared_workers)
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "new file recovers from dead shared worker" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            try
                QNR.run!(s, a)
                QNR.run!(s, b)
                old_pid = s.workers[abspath(a)].worker.proc_pid

                # Kill worker directly
                file_a = s.workers[abspath(a)]
                Base.kill(file_a.worker.proc, Base.SIGKILL)
                while QNR.WorkerIPC.isrunning(file_a.worker)
                    sleep(0.01)
                end

                # Close stale files
                QNR.close!(s, abspath(a))
                QNR.close!(s, abspath(b))

                # Create a new file — should recover with a fresh worker
                c = write_qmd(dir, "c.qmd")
                QNR.run!(s, c)
                new_pid = s.workers[abspath(c)].worker.proc_pid
                @test new_pid != old_pid
                @test length(s.shared_workers) == 1
            finally
                QNR.close!(s)
            end
        end
    end

    @testset "concurrent rendering on shared worker" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "x = 1 + 1")
            b = write_qmd(dir, "b.qmd"; code = "y = 2 + 2")
            s = QNR.Server()
            try
                # First run to create both files on shared worker
                QNR.run!(s, a)
                QNR.run!(s, b)
                @test s.workers[abspath(a)].worker === s.workers[abspath(b)].worker

                # Concurrent re-renders
                task_a = Threads.@spawn QNR.run!(s, a)
                task_b = Threads.@spawn QNR.run!(s, b)
                result_a = fetch(task_a)
                result_b = fetch(task_b)
                @test result_a.cells[2].outputs[1].data["text/plain"] == "2"
                @test result_b.cells[2].outputs[1].data["text/plain"] == "4"
            finally
                QNR.close!(s)
            end
        end
    end
end
