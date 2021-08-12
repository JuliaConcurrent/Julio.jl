module TestLocks

using ArgCheck: @check
using Julio
using Test
using ..Utils: trywait

function test_trivial()
    lck = Julio.Lock()
    lock(lck)
    unlock(lck)
    @test true
end

function test_reentrancy()
    lck = Julio.Lock()
    Julio.withtaskgroup() do tg
        lock(lck)
        t = Julio.spawn!(tg) do
            lock(lck)
            unlock(lck)
        end
        @test !trywait(t)
        lock(lck)
        lock(lck)
        unlock(lck)
        unlock(lck)
        @test !trywait(t)
        unlock(lck)
        @test trywait(t, 3)
    end
    @test true
end

function test_exclusivity()
    lck = Julio.Lock()
    Julio.withchannel() do i1, o1
        Julio.withqueue() do i2, o2
            Julio.withtaskgroup() do tg
                Julio.spawn!(tg) do
                    lock(lck) do
                        put!(i1, :acquired)
                        put!(i1, :releasing)
                        put!(i2, :t1_releasing)
                    end
                end
                @test take!(o1) === :acquired
                @check !trylock(lck)
                Julio.spawn!(tg) do
                    put!(i2, :t2_locking)
                    lock(lck) do
                        put!(i2, :t2_acquired)
                    end
                end
                @test take!(o2) === :t2_locking
                @test take!(o1) === :releasing
                @test take!(o2) === :t1_releasing
                @test take!(o2) === :t2_acquired
            end
        end
    end
end

function test_repeat(; ntasks = Threads.nthreads() * 4, nrepeat = 1000)
    lck = Julio.Lock()
    Julio.withtaskgroup() do tg
        for _ in 1:ntasks
            Julio.spawn!(tg) do
                for i in 1:nrepeat
                    lock(lck) do
                    end
                    # i % 16 == 0 && Julio.yield()
                end
            end
        end
    end
    @test true
end

end  # module
