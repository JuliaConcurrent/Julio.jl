module TestChannels

using ArgCheck
using Julio
using Julio.Internal: @trace
using Test
using ..Utils: random_sleep, trywait

function test_after_close()
    @testset for f in [Julio.stack, Julio.queue]
        test_after_close(f)
    end
end

function test_after_close(f)
    ih, oh = f(Int)
    Julio.open(ih) do ie
        put!(ie, 111)
    end
    Julio.open(oh) do oe
        @test take!(oe) == 111
    end
end

function test_close_many()
    @testset for f in [Julio.stack, Julio.queue, Julio.channel]
        test_close_many(f)
    end
end

function test_close_many(f)
    ih, oh = f(Int)
    ie1 = open(ih)
    ie2 = open(ih)
    t = @task open(collect, oh)
    yield(t)
    put!(ie1, 111)
    close(ie1)
    close(ie1)
    @test !trywait(t)
    put!(ie2, 222)
    close(ie2)
    @check trywait(t, 3)
    @test fetch(t) == [111, 222]
end

function test_queue()
    @testset for f in [Julio.channel, Julio.queue]
        test_queue(f)
    end
end

function test_queue(f)
    fst = Ref(0)
    snd = Ref(0)
    ih, oh = f(Int)
    Julio.openall(ih, oh) do ie, oe
        Julio.withtaskgroup() do tg
            Julio.spawn!(tg) do
                put!(ie, 111)
                put!(ie, 222)
            end
            Julio.spawn!(tg) do
                fst[] = take!(oe)
                snd[] = take!(oe)
            end
        end
    end
    @test (fst[], snd[]) == (111, 222)
end

function test_stack()
    fst = Ref(0)
    snd = Ref(0)
    Julio.withtaskgroup() do tg
        ih, oh = Julio.stack(Int)
        Julio.open(ih) do ie
            put!(ie, 111)
            put!(ie, 222)
        end
        Julio.open(oh) do oe
            fst[] = take!(oe)
            snd[] = take!(oe)
        end
    end
    @test (fst[], snd[]) == (222, 111)
end

function test_clone()
    @testset for f in [Julio.channel, Julio.stack, Julio.queue]
        test_clone(f)
    end
end

function test_clone(f; nrepeat = 100)
    @testset for trial in 1:nrepeat
        check_clone(f)
    end
end

function check_clone(f)
    fst = Ref(0)
    snd = Ref(0)
    Julio.withtaskgroup() do tg
        ih, oh = f(Int)
        Julio.open(ih) do ie
            Julio.spawn!(tg, oh) do oe
                random_sleep()
                @trace label = :pre_take1
                fst[] = take!(oe)
                @trace label = :pre_take2
                snd[] = take!(oe)
            end
            Julio.spawn!(tg, Julio.clone(ie)) do ie
                random_sleep()
                put!(ie, 111)
            end
            Julio.spawn!(tg, Julio.clone(ie)) do ie
                random_sleep()
                put!(ie, 222)
            end
        end
    end
    @test sort!([fst[], snd[]]) == [111, 222]
end

function test_stack_iterate(; nrepeat = 100, kwargs...)
    @testset for trial in 1:nrepeat
        check_stack_iterate()
    end
end

function check_stack_iterate(; nitems = 100, kwargs...)
    Julio.withtaskgroup() do tg
        ih, oh = Julio.stack(Int)
        Julio.spawn!(tg, ih) do ie
            for i in 1:nitems
                put!(ie, i)
            end
        end
        Julio.open(oh) do oe
            received = collect(oe)
            sort!(received)
            @test length(received) == nitems
            @test received == 1:nitems
        end
    end
end

function test_queue_iterate()
    @testset for f in [Julio.channel, Julio.queue]
        test_queue_iterate(f)
    end
end

function test_queue_iterate(f; nrepeat = 100, kwargs...)
    @testset for trial in 1:nrepeat
        check_queue_iterate(f; kwargs...)
    end
end

function check_queue_iterate(f; nitems = 100)
    Julio.withtaskgroup() do tg
        ih, oh = f(Int)
        Julio.open(oh) do oe
            Julio.spawn!(tg, ih) do ie
                for i in 1:nitems
                    put!(ie, i)
                end
            end
            received = collect(oe)
            @test length(received) == nitems
            @test received == 1:nitems
        end
    end
end

function test_any_type_blocking()
    @testset for f in [Julio.stack, Julio.queue]
        test_any_type_blocking(f)
    end
end

function test_any_type_blocking(f)
    ih, oh = f()
    Julio.open(ih) do ie
        put!(ie, 111)
    end
    Julio.open(oh) do oe
        @test take!(oe) == 111
    end
end

function test_any_type_async()
    @testset for f in [Julio.channel, Julio.stack, Julio.queue]
        test_any_type_async(f)
    end
end

function test_any_type_async(f)
    Julio.withtaskgroup() do tg
        ih, oh = f()
        Julio.open(oh) do oe
            Julio.spawn!(tg, ih) do ie
                put!(ie, 111)
            end
            @test take!(oe) == 111
        end
    end
end

# Like `test_channel_open_many_scoped` but using the "less strict" API:
function test_channel_open_many_scoped2()
    Julio.withchannel() do input_endpoint, output_endpoint
        local task
        Julio.withtaskgroup() do tg0
            task = Julio.spawn!(tg0) do
                sort!(collect(output_endpoint))
            end
            try
                Julio.withtaskgroup() do tg1
                    for i in 1:10
                        Julio.spawn!(tg1) do
                            put!(input_endpoint, i)
                        end
                    end
                end
            finally
                close(input_endpoint)
            end
        end
        @test fetch(task) == 1:10
    end
end

end  # module
