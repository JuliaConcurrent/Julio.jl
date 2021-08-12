# # [Select](@id man-select)

using Julio: Julio, Events
using Test

# `Julio.select` can be used for executing exactly one ready *event* from a set
# of events.

# ## Selecting a queue

function test_simple_select()
    #=
    To demonstrate how `Julio.select` works, suppose that we have multiple
    queues and waiting for an element from them.
    =#
    qin1, qout1 = Julio.openqueue()  # input/output handles for the first queue
    qin2, qout2 = Julio.openqueue()  # input/output handles for the second queue
    #=
    Suppose there is an element in the second queue:
    =#
    put!(qin2, 222)
    #=
    Then waiting on `take!` event of an empty queue and a nonempty queue
    does not block. It executes the `take!` event on the nonempty queue:
    =#
    selected = nothing
    Julio.select(
        (take!, qout1) => item -> begin
            selected = item
        end,
        (take!, qout2) => item -> begin
            selected = item
        end,
    )
    @test selected == 222
    #=
    ---
    =#
end

# ## Selecting an arbitrary event

# `Julio.select` can also be used with various events.

function test_mixed_select()
    #=
    It supports, for example, unbuffered channel:
    =#
    chi, cho = Julio.openchannel()
    #=
    ...and read/write on `IO` objects such as a pipe:
    =#
    Julio.open(`echo "hello"`) do output
        #=
        ...and acquiring locks:
        =#
        lck = Julio.Lock()
        # t = @task lock(lck)   #src
        # yield(t)              #src

        #=
        When the `Base` API `$f` has keyword arguments, you can use
        `Julio.Events.$f` to create an event.  Note that `($f, args...)` is
        equivalent to `Julio.Events.$f(args...)`.
        =#
        selected = nothing
        Julio.select(
            Events.readline(output; keep = true) => item -> begin
                selected = item
            end,
            Events.lock(lck) => _ -> begin
                unlock(lck)
                selected = :lock
            end,
            (put!, chi, 1) => _ -> begin
                selected = :put_1
            end,
        )
        #=
        In the above example, since the `output` pipe and the `lock` are
        both ready, `Julio.select` can select any one of them. However,
        since there is no other task `take!`ing the element from the channel
        `cho`, the `put!` event can not be selected.
        =#
        @test selected in ("hello\n", :lock)
        #=
        If `Events.lock(lck)` was selected, the `output` is not consumed:
        =#
        if selected === :lock
            @test readline(output) == "hello"
        end
        #=
        ---
        =#
    end
end

# ## [Example: bounding search results](@id ex-bounding-search)
#
# Suppose we need to move at least `minitems` items from one channel to another
# while filtering them using a predicate function `f`. Furthermore, we don't
# want to loose any items. That is to say, once an item is taken from the input
# channel, it must be put into the output channel (unless `f` evaluates to
# false).  Note that the we cannot use the [cancel scope](@ref man-cancel-scope)
# (naively) due to the last requirement; i.e., it is not correct to cancel the
# task when it's blocked while putting the item to the output channel. While we
# can still use the cancel scope by surrounding post-`take!` code in a
# `Julio.shield` block, the folowing code demonstrates more straightforward
# approach based on `Julio.select`.
#
# To setup cancellation specific to one event (`take!`), we can use explicit
# "cancellation token" and combine it with the original event.

using Julio: maybetake!, tryput!

function channel_filter!(f, output, input, minitems; ntasks = 4 * Threads.nthreads())
    nitems = Threads.Atomic{Int}(0)
    done = Julio.Promise{Nothing}()  # cancellation token
    Julio.withtaskgroup() do tg
        for _ in 1:ntasks
            Julio.spawn!(tg) do
                while true
                    m = Julio.select(
                        (fetch, done) => Returns(nothing),  # return nothing when done
                        (maybetake!, input),  # return Some(x) if we took x
                    )
                    x = @something(m, break)  # break if done
                    if f(x)
                        put!(output, x)
                        # If enough items have been sent, signal other tasks to finish.
                        if Threads.atomic_add!(nitems, 1) + 1 >= minitems
                            tryput!(done, nothing)
                            break
                        end
                    end
                end
            end
        end
    end
end

# In the above example, we use `(Julio.maybetake!, input)` event instead of
# `(take!, input)` event.  This is for handling the case `input` is closed.
# That is to say, `m === nothing` if `input` is closed or `tryput!(done,
# nothing)` has been executed.

function test_channel_filter()
    Julio.withtaskgroup() do tg
        ih1, oh1 = Julio.channel()
        ih2, oh2 = Julio.channel()
        Julio.openall(oh1, oh2) do oe1, oe2
            Julio.spawn!(tg, ih1) do ie1
                for i in 1:15
                    put!(ie1, i)
                end
            end
            Julio.spawn!(tg, ih2, oh1) do ie2, oe1
                channel_filter!(isodd, ie2, oe1, 3; ntasks = 2)
            end
            out2 = collect(oe2)
            out1 = collect(oe1)
            sort!(out2)
            sort!(out1)
            @test length(out2) >= 3  # `channel_filter!` produced at least 3 elements
            @test out2 == (1:length(out2)) .* 2 .- 1
            @test out1 == out1[1]:out1[end]
        end
    end
end
