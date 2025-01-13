win = Sys.iswindows()

@testset "Interrupt: $W" for W in (m.DistributedStdlibWorker, m.InProcessWorker, m.Worker)
# @testset "Interrupt: $W" for W in (m.Worker,)
    
    no_interrupt_possible = (Sys.iswindows() && W === m.DistributedStdlibWorker) || W === m.InProcessWorker


    w = W()

    @test m.isrunning(w)
    @test m.remote_call_fetch(&, w, true, true)
    
    
    ex1 = quote
        local x = 0.0
        for i = 1:4000
            k = [sqrt(abs(sin(cos(tan(x))))) ^ (1 / i) for z in 1:i]
            x += sum(k)
        end
        x
    end |> Base.remove_linenums!
    
    ex2 = quote
        local x = 0.0
        for i in 1:20_000_000
            x += sqrt(abs(sin(cos(tan(x)))))^(1/i)
        end
        x
    end |> Base.remove_linenums!
    
    ex3 = :(sleep(3)) |> Base.remove_linenums!
    
    # expressions in this list can be interrupted with a single Ctrl+C
    # open a terminal and try this.
    # (some expressions like `while true end` need multiple Ctrl+C in short succession to force throw SIGINT)
    exs = no_interrupt_possible ? [ex1, ex3] : [
        ex1,
        ex3,
        ex1, # second time because interrupts should be reliable
        (
            VERSION > v"1.10.0-0" ? [ex2, ex2] : []
        )...,
    ]
    
    

    @testset "single interrupt $ex" for ex in exs
        
        f() = m.remote_eval(w, ex)
        
        t1 = @elapsed wait(f())
        t2 = @elapsed wait(f())
        
        t3 = @elapsed begin
            t = f()
            @test !istaskdone(t)
            sleep(.1)
            m.interrupt(w)
            r = try
                fetch(t)
            catch e
                e
            end
            no_interrupt_possible || @test r isa TaskFailedException
        end
        
        t4 = @elapsed begin
            t = f()
            @test !istaskdone(t)
            sleep(.1)
            m.interrupt(w)
            r = try
                fetch(t)
            catch e
                e
            end
            no_interrupt_possible || @test r isa TaskFailedException
        end
        
        @info "test run" ex t1 t2 t3 t4
        no_interrupt_possible || @test t4 < min(t1,t2) * 0.8
        
        # still running and responsive
        @test m.isrunning(w)
        @test m.remote_call_fetch(&, w, true, true)
        
    end
    
    
    if !no_interrupt_possible
        @testset "hard interrupt" begin
                    
            function hard_interrupt(w)
                finish_task = m.remote_call(&, w, true, true)
            
                done() = !m.isrunning(w) || istaskdone(finish_task)
                
                while !done()
                    for _ in 1:5
                        print(" 🔥 ")
                        m.interrupt(w)
                        sleep(0.18)
                        if done()
                            break
                        end
                    end
                    sleep(1.5)
                end
            end
            
            
            t = m.remote_eval(w, :(while true end))
            
            @test !istaskdone(t)
            @test m.isrunning(w)
            
            hard_interrupt(w)
            
            
            @info "xx" istaskdone(t) m.isrunning(w)
            
            @test try
                fetch(t)
            catch e
                e
            end isa TaskFailedException
            
            # hello
            @test true
            
            if Sys.iswindows() && VERSION < v"1.10.0-beta3"
                # fixed by https://github.com/JuliaLang/julia/pull/51307 which will probably land in v1.10.0-beta3
                @test_broken m.isrunning(w)
            else
                # still running and responsive
                @test m.isrunning(w)
                @test m.remote_call_fetch(&, w, true, true)
            end
        end
    end
    
    
    m.stop(w)
    @test !m.isrunning(w)
end
