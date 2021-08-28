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
    ie, oe = f(Int)
    put!(ie, 111)
    close(ie)
    @test take!(oe) == 111
end

function test_close_many()
    @testset for f in [Julio.stack, Julio.queue, Julio.channel]
        test_close_many(f)
    end
end

function test_close_many(f)
    ie, oe = f(Int)
    t = @task collect(oe)
    yield(t)
    put!(ie, 111)
    @test !trywait(t)
    put!(ie, 222)
    close(ie)
    close(ie)
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
    ie, oe = f(Int)
    try
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
    finally
        close(ie)
        close(oe)
    end
    @test (fst[], snd[]) == (111, 222)
end

function test_stack()
    fst = Ref(0)
    snd = Ref(0)
    begin
        ie, oe = Julio.stack(Int)
        try
            put!(ie, 111)
            put!(ie, 222)
        finally
            close(ie)
        end
        try
            fst[] = take!(oe)
            snd[] = take!(oe)
        finally
            close(oe)
        end
    end
    @test (fst[], snd[]) == (222, 111)
end

function test_stack_iterate(; nrepeat = 100, kwargs...)
    @testset for trial in 1:nrepeat
        check_stack_iterate()
    end
end

function check_stack_iterate(; nitems = 100, kwargs...)
    Julio.withtaskgroup() do tg
        ie, oe = Julio.stack(Int)
        Julio.spawn!(tg) do
            try
                for i in 1:nitems
                    put!(ie, i)
                end
            finally
                close(ie)
            end
        end
        try
            received = collect(oe)
            sort!(received)
            @test length(received) == nitems
            @test received == 1:nitems
        finally
            close(oe)
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
        ie, oe = f(Int)
        Julio.spawn!(tg) do
            try
                for i in 1:nitems
                    put!(ie, i)
                end
            finally
                close(ie)
            end
        end
        try
            received = collect(oe)
            @test length(received) == nitems
            @test received == 1:nitems
        finally
            close(oe)
        end
    end
end

function test_any_type_blocking()
    @testset for f in [Julio.stack, Julio.queue]
        test_any_type_blocking(f)
    end
end

function test_any_type_blocking(f)
    ie, oe = f()
    put!(ie, 111)
    @test take!(oe) == 111
end

function test_any_type_async()
    @testset for f in [Julio.channel, Julio.stack, Julio.queue]
        test_any_type_async(f)
    end
end

function test_any_type_async(f)
    Julio.withtaskgroup() do tg
        ie, oe = f()
        Julio.spawn!(tg) do
            try
                put!(ie, 111)
            finally
                close(ie)
            end
        end
        try
            @test take!(oe) == 111
        finally
            close(oe)
        end
    end
end

# Like `test_channel_open_many_scoped` but using the "less strict" API:
function test_channel_open_many_scoped2()
    send_endpoint, receive_endpoint = Julio.channel()
    try
        local task
        Julio.withtaskgroup() do tg0
            task = Julio.spawn!(tg0) do
                sort!(collect(receive_endpoint))
            end
            try
                Julio.withtaskgroup() do tg1
                    for i in 1:10
                        Julio.spawn!(tg1) do
                            put!(send_endpoint, i)
                        end
                    end
                end
            finally
                close(send_endpoint)
            end
        end
        @test fetch(task) == 1:10
    finally
        close(send_endpoint)
        close(receive_endpoint)
    end
end

end  # module
