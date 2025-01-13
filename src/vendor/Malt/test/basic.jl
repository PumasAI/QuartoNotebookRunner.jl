
# NOTE: These tests are just sanity checks.
# They don't try to find edge cases or anything,
# If they fail something is definitely wrong.
# More tests should be added in the future.


@testset "Impl: $W" for W in (m.DistributedStdlibWorker, m.InProcessWorker, m.Worker)
    @testset "Worker management" begin
        w = W()
        @test m.isrunning(w) === true
        @test m.remote_call_fetch(&, w, true, true)

        W === m.Worker && @test length(m.__iNtErNaL_get_running_procs()) == 1
        
        if W === m.InProcessWorker
            m.stop(w)
        else
            start = time()
            task = m.remote_call(sleep, w, 10)
            
            m.stop(w)
            
            @test try
                wait(task)
            catch e
                e
            end isa TaskFailedException
            stop = time()
            @test stop - start < 8
        end
        
        
        @test m.isrunning(w) === false
        W === m.Worker && @test length(m.__iNtErNaL_get_running_procs()) == 0
    end


    @testset "Evaluating functions" begin
        w = W()
        @test m.isrunning(w)
        @test m.remote_call_fetch(&, w, true, true)

        m.stop(w)
    end


    @testset "Evaluating expressions" begin
        w = W()
        @test m.isrunning(w) === true
        
        @test m.remote_eval_fetch(Main, w, :(1 + 1)) == 2
        @test m.remote_eval_fetch(Main, w, nothing) === nothing
        @test m.remote_eval_wait(Main, w, nothing) === nothing

        m.remote_eval_wait(Main, w, :(module Stub end))

        str = "x is in Stub"

        m.remote_eval_wait(Main, w, quote
            Core.eval(Stub, :(x = $$str))
        end)

        @test m.remote_eval_fetch(Main, w, :(Stub.x)) == str

        m.stop(w)
    end
    
    @testset "Async things" begin
        w = W()
        
        @test m.remote_eval_fetch(w, :(x = 1 + 1)) == 2
        @test m.remote_eval_fetch(w, :x) == 2
        
        # this should run async
        m.remote_eval(w, quote
            sleep(.5)
            x = 900
        end)
        
        @test m.remote_eval_fetch(w, :x) == 2
        sleep(.55)
        @test m.remote_eval_fetch(w, :x) == 900
        
        # this should run async
        m.remote_do(Core.eval, w, Main, quote
            sleep(.5)
            x = 400
        end)
        
        @test m.remote_eval_fetch(w, :x) == 900
        sleep(.55)
        @test m.remote_eval_fetch(w, :x) == 400
        
        m.stop(w)
    end


    @testset "Worker channels" begin
        w = W()

        channel_size = 20
        
        lc = m.worker_channel(w, :(rc = Channel($channel_size)))
        
        if w isa m.DistributedStdlibWorker
            @test_broken lc isa AbstractChannel
        else
            @test lc isa AbstractChannel
        end

        @testset for _i in 1:10
            n = rand(Int)

            m.remote_eval_wait(Main, w, quote
                put!(rc, $(n))
            end)

            @test take!(lc) === n
            put!(lc, n)
            @test take!(lc) === n
            put!(lc, n)
            put!(lc, n)
            @test take!(lc) === n
            @test take!(lc) === n
            
        end
        
        
        
        t = @async begin
            for i in 1:2*channel_size
                @test take!(lc) == i
            end
            @test !isready(lc)
        end
        
        for i in 1:2*channel_size
            put!(lc, i)
        end
        
        wait(t)
        
        

        m.stop(w)
    end

    @testset "Signals" begin
        w = W()

        m.remote_eval(Main, w, quote
            sleep(1_000_000)
        end)

        m.interrupt(w)
        @test m.isrunning(w) === true

        m.stop(w)
        @test m.isrunning(w) === false
    end
end