macro catcherror(ex)
    return quote
        local success
        e = try
            $(esc(ex))
            success = true
        catch e
            success = false
            e
        end
        @assert !success "Expression did not throw :("
        e
    end
end

# To test serialization
struct LocalStruct end

# @testset "Exceptions" begin
@testset "Exceptions: $W" for W in (
        m.DistributedStdlibWorker, 
        m.Worker, 
        m.InProcessWorker, 
    )
    
    CallFailedException = m.RemoteException
    CallFailedAndDeserializationOfExceptionFailedException = m.RemoteException
    # Distributed cannot easily distinguish between a call that failed and a call that returned something that could not be deserialized by the host.
    DeserializationFailedException = W === m.DistributedStdlibWorker ? Exception : ErrorException
    
    
    
    w = W() # does not apply to Malt.InProcessWorker
    
    
    @testset "Remote failure" begin
        # m.remote_eval_wait(w, :(sqrt(-1)))
        
        @test_throws(
            CallFailedException,
            m.remote_eval_wait(w, :(sqrt(-1))),
        )
        # searching for strings requires Julia 1.8
        VERSION >= v"1.8.0" && @test_throws(
            ["Remote exception", "DomainError", "math.jl"],
            m.remote_eval_wait(w, :(sqrt(-1))),
        )
        @test_throws(
            TaskFailedException,
            wait(m.remote_eval(w, :(sqrt(-1)))),
        )
        
        @test_nowarn m.remote_do(sqrt, w, -1)
        
        @test m.remote_call_fetch(&, w, true, true)
    end
    
    W === m.InProcessWorker || @testset "Deserializing values of unknown types" begin
        stub_type_name = gensym(:NonLocalType)

        m.remote_eval_wait(w, quote
            struct $(stub_type_name) end
        end)
        # TODO
        m.remote_eval_wait(w, :($stub_type_name()))
        @test_throws(
            DeserializationFailedException,
            m.remote_eval_fetch(w, :($(stub_type_name)())),
        )
        @test_throws(
            TaskFailedException,
            fetch(m.remote_eval(w, :($(stub_type_name)()))),
        )
        @test m.remote_call_fetch(&, w, true, true)
    end

    stub_type_name2 = gensym(:NonLocalException)

    m.remote_eval_wait(w, quote
        struct $stub_type_name2 <: Exception end
        Base.showerror(io::IO, e::$stub_type_name2) = print(io, "secretttzz")
    end)

    @testset "Throwing unknown exception" begin
        
        @test_throws(
            CallFailedAndDeserializationOfExceptionFailedException,
            m.remote_eval_fetch(w, :(throw($stub_type_name2()))),
        )
        # searching for strings requires Julia 1.8
        VERSION >= v"1.8.0" && @test_throws(
            ["Remote exception", W !== m.DistributedStdlibWorker ? "secretttzz" : "deseriali"],
            m.remote_eval_fetch(w, :(throw($stub_type_name2()))),
        )
        @test_throws(
            TaskFailedException,
            fetch(m.remote_eval(w, :(throw($stub_type_name2())))),
        )

        @test m.remote_call_fetch(&, w, true, true)
    end

    @testset "Returning an exception" begin
        
        @test_nowarn m.remote_eval_fetch(w, quote
            try
                sqrt(-1)
            catch e
                e
            end
        end)
        
        ## Catching unknown exceptions and returning them as values also causes an exception.
        W === m.InProcessWorker || @test_throws(
            DeserializationFailedException,
            m.remote_eval_fetch(w, quote
                try
                    throw($stub_type_name2())
                catch e
                    e
                end
            end),
        )
        
        
        # TODO
        @test_throws(
            Exception,
            m.worker_channel(w, :(123))
        )
        @test_throws(
            m.RemoteException,
            m.worker_channel(w, :(sqrt(-1)))
        )
        @test m.remote_call_fetch(&, w, true, true)
    end

    W === m.Worker && @testset "Serialization error" begin
        @test_throws m.RemoteException m.remote_eval_fetch(w, quote
            $(LocalStruct)()
        end)
    end

    # The worker should be able to handle all that throwing
    @test m.isrunning(w)

    m.stop(w)
    @test !m.isrunning(w)
end
