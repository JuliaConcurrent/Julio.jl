module TestHappyEyeballs

nolatencies(_) = nothing
const INJECTOR = Ref{Any}(nolatencies)

inject_latencies(islast) = INJECTOR[](islast)

include("../../../examples/happy_eyeballs.jl")

function with_latencies(f, injector)
    old = INJECTOR[]
    INJECTOR[] = injector
    try
        f()
    finally
        INJECTOR[] = old
    end
end

function sleep1_if_not_last(islast)
    if !islast
        sleep(1)
    end
end

function random_latencies(_)
    sleep(rand(0.1:0.1:1.5))
end

function test_happy_eyeballs_with_sleep1_if_not_last()
    with_latencies(sleep1_if_not_last) do
        @testset for trial in 1:3
            test_happy_eyeballs()
        end
    end
end

function test_happy_eyeballs_with_random_latencies()
    with_latencies(random_latencies) do
        @testset for trial in 1:3
            test_happy_eyeballs()
        end
    end
end

end  # module
