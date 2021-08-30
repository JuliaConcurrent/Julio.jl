module TestDyingPhilosopher

sleep(x) = SLEEP_IMPL[](x)
const SLEEP_IMPL = Ref{Any}(Base.sleep)

println(x) = PRINTLN_IMPL[](x)
const PRINTLN_IMPL = Ref{Any}(Base.println)

include("../../../examples/dying_philosopher.jl")

using Test

function patch_with(f, ref, impl)
    old = ref[]
    ref[] = impl
    try
        f()
    finally
        ref[] = old
    end
end

function run_dying_philosopher(nphils = 5)
    outputs = Channel(Inf)  # not using Julio's to avoid cancellation
    function println_impl(x)
        put!(outputs, x)
    end

    nsleeps = Threads.Atomic{Int}(0)
    alllocked = Julio.Promise{Nothing}()
    function sleep_impl(time)
        if time <= 1
            # sleep(rand()) call
            if Threads.atomic_add!(nsleeps, 1) + 1 == nphils
                alllocked[] = nothing
            else
                alllocked[]
            end
        else
            # sleep(10) call
            alllocked[]
        end
    end

    patch_with(SLEEP_IMPL, sleep_impl) do
        patch_with(PRINTLN_IMPL, println_impl) do
            dying_philosopher(nphils)
        end
    end

    close(outputs)
    return collect(outputs)
end

function test_dying_philosopher(nphils = 5)
    outputs = run_dying_philosopher(nphils)
    @test startswith(outputs[1], "Killing")
    @test startswith(outputs[2], "But what is death?")
    @test all(startswith.(outputs[3:end][1:nphils-1], "eating"))
end

end  # module
