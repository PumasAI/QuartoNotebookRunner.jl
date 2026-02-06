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
            QNR.run!(s, a)
            QNR.run!(s, b)
            # Both files tracked separately
            @test length(s.workers) == 2
            # But share one worker process
            @test s.workers[abspath(a)].worker === s.workers[abspath(b)].worker
            @test length(s.shared_workers) == 1
            entry = first(values(s.shared_workers))
            @test Set([abspath(a), abspath(b)]) == entry.users
            QNR.close!(s)
        end
    end

    @testset "different exeflags get separate workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; exeflags = "--check-bounds=yes")
            b = write_qmd(dir, "b.qmd"; exeflags = "--check-bounds=no")
            s = QNR.Server()
            QNR.run!(s, a)
            QNR.run!(s, b)
            @test length(s.workers) == 2
            @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
            @test length(s.shared_workers) == 2
            QNR.close!(s)
        end
    end

    @testset "default (no share) creates separate workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; share = false)
            b = write_qmd(dir, "b.qmd"; share = false)
            s = QNR.Server()
            QNR.run!(s, a)
            QNR.run!(s, b)
            @test length(s.workers) == 2
            @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
            @test isempty(s.shared_workers)
            QNR.close!(s)
        end
    end

    @testset "mixed shared and non-shared stay separate" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; share = true)
            b = write_qmd(dir, "b.qmd"; share = false)
            s = QNR.Server()
            QNR.run!(s, a)
            QNR.run!(s, b)
            @test length(s.workers) == 2
            @test s.workers[abspath(a)].worker !== s.workers[abspath(b)].worker
            @test length(s.shared_workers) == 1
            QNR.close!(s)
        end
    end

    @testset "close one shared notebook, worker survives for other" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
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
            QNR.close!(s)
        end
    end

    @testset "close!(server) cleans up shared workers" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd")
            b = write_qmd(dir, "b.qmd")
            s = QNR.Server()
            QNR.run!(s, a)
            QNR.run!(s, b)
            @test length(s.shared_workers) == 1
            QNR.close!(s)
            @test isempty(s.workers)
            @test isempty(s.shared_workers)
        end
    end

    @testset "shared notebooks have isolated evaluation contexts" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "x = 42")
            b = write_qmd(dir, "b.qmd"; code = "#| error: true\nx")
            s = QNR.Server()
            QNR.run!(s, a)
            result = QNR.run!(s, b)
            @test s.workers[abspath(a)].worker === s.workers[abspath(b)].worker
            # B's cell should have an UndefVarError — x from A is not visible
            output = result.cells[2].outputs[1]
            @test output.output_type == "error"
            @test output.ename == "UndefVarError"
            QNR.close!(s)
        end
    end

    @testset "re-render shared notebook works" begin
        mktempdir() do dir
            a = write_qmd(dir, "a.qmd"; code = "x = 42")
            b = write_qmd(dir, "b.qmd"; code = "y = 99")
            s = QNR.Server()
            QNR.run!(s, a)
            QNR.run!(s, b)
            pid = s.workers[abspath(a)].worker.proc_pid

            # Re-render a — refresh! should work without restarting worker
            QNR.run!(s, a)
            @test s.workers[abspath(a)].worker.proc_pid == pid
            @test length(s.shared_workers) == 1
            QNR.close!(s)
        end
    end
end
