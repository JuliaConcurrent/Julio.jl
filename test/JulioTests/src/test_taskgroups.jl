module TestTaskGroups

using Julio
using Test

function test_trivial_spawns()
    ref1 = Ref(0)
    ref2 = Ref(0)
    Julio.withtaskgroup() do tg
        Julio.spawn!(tg) do
            ref1[] = 111
        end
        Julio.spawn!(tg) do
            ref2[] = 222
        end
    end
    @test (ref1[], ref2[]) == (111, 222)
end

function test_cancel_with_single_main_error()
    err_cause = ErrorException("error in main")
    err = try
        Julio.withtaskgroup() do tg
            _ie, oe = Julio.channel()
            Julio.spawn!(tg) do
                take!(oe)  # should be unblocked by cancellation
            end
            throw(err_cause)
        end
        nothing
    catch err
        err
    end
    @test err == err_cause
end

end  # module
