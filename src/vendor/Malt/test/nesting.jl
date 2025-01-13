@testset "Nesting" begin


    w = m.Worker()

    @test m.remote_eval_fetch(Main, w, quote
        copy!(LOAD_PATH, $(LOAD_PATH))
        import Malt as m

        w = m.Worker()

        result = m.remote_eval_fetch(Main, w, :(1 + 1)) == 2

        m.stop(w)
        m._wait_for_exit(w)

        result
    end)


    @test m.remote_eval_fetch(Main, w, quote
        copy!(LOAD_PATH, $(LOAD_PATH))
        import Malt as m

        w = m.Worker()

        result = m.remote_eval_fetch(Main, w, quote
            
            copy!(LOAD_PATH, $(LOAD_PATH))
            import Malt as m

            w = m.Worker()

            result = m.remote_eval_fetch(Main, w, :(1 + 1)) == 2

            m.stop(w)
            m._wait_for_exit(w)

            result
        end)

        m.stop(w)
        m._wait_for_exit(w)

        result
    end)

    m.stop(w)
    m._wait_for_exit(w)

end