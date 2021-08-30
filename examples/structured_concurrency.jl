# # Structured concurrency

using Julio
using Test

# ## [Black box rule](@id black-box)
#
# In sequential programs, the side-effects of a function are "done" by the time
# the function returns [^closure]. However, many concurrent programming paradims
# do not let us assume such a simple but yet highly useful property. In [Notes
# on structured concurrency, or: Go statement considered harmful — njs
# blog](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)
# (See also: [Trio: Async concurrency for mere mortals - PyCon 2018 -
# YouTube](https://www.youtube.com/watch?v=oLkfnc_UMcE)), Nathaniel J. Smith
# called this property the *"black box rule"*.
#
# [^closure]: Programming constructs such as closures, coroutines, and "methods"
#     in class-based object oriented programming languages may be considered as
#     mechanisms for "resuming" the side-effects. However, they have visible
#     syntax (e.g., function call) for resuming the side-effect. Thus, these
#     constructs still follow the black box rule.
#
# ### Programming without the black box rule
#
# To demonstrate the pain comes with functions that does not follow the black
# box rule, let us consider the following simple function:

function channel_map_unstructured!(f, output, input; ntasks = Threads.nthreads())
    for _ in 1:ntasks
        Threads.@spawn for x in input
            y = f(x)
            put!(output, y)
        end
    end
end

# This function `channel_map_unstructured!` does not follow the black box rule
# because it does not wait for the spawned tasks; i.e., these "leaked" tasks are
# keep mutating `output` and `input` even after `channel_map_unstructured!`
# returns.  Programs using such functions like this are very hard to understand.

function test_channel_map_unstructured()
    #=
    Suppose we need to combine the result of two kinds of "computations" into
    one output channel (`source_channel` is defined below):
    =#
    output = Channel()
    channel_map_unstructured!(output, source_channel(1:100); ntasks = 10) do x
        sleep(0.01)
        2x
    end
    channel_map_unstructured!(output, source_channel(1:100); ntasks = 10) do x
        sleep(0.01)
        2x + 1
    end
    #=
    It is tricky to accumulate the result reliably (another disadvantage of
    unstructured concurrencty).  For this demonstration, we can "cheat" since we
    know the size of the output.
    =#
    results = []
    for _ in 1:200
        push!(results, take!(output))
    end
    close(output)
    #=
    Ideally, the program order is reflected in the result. If it were the case,
    we should see even numbers first and then odd numbers. However, since
    `channel_map_unstructured!` violates the black box rule and the "leaked"
    tasks are keep adding results to the `output` channel, we can't understand
    the program by looking at the invocations of `channel_map_unstructured!`.
    =#
    @test_broken all(iseven, results[1:end÷2])
    @test_broken all(isodd, results[end÷2+1:end])
    #=
    ---
    =#
end

# (The above example uses a simple utility function `source_channel` for
# generating the input source:)

function source_channel(xs)
    ch = Channel(Inf)
    for x in xs
        put!(ch, x)
    end
    close(ch)
    return ch
end

# ### Julio API enforces the black box rule
#
# Julio "enforces" the black box rule by providing API such that `Julio.spawn!`
# can be called only within a dynamical scope of `Julio.withtaskgroup`.  Thus,
# mechanically translating `channel_map_unstructured!` to use Julio API gives us
# a function that follows the black box rule.

function channel_map_structured!(f, output, input; ntasks = Threads.nthreads())
    Julio.withtaskgroup() do tg
        for _ in 1:ntasks
            Julio.spawn!(tg) do
                for x in input
                    y = f(x)
                    put!(output, y)
                end
            end
        end
    end
end

function test_channel_map_structured()
    send_endpoint, eh = Julio.queue()
    try
        try
            channel_map_structured!(send_endpoint, source_channel(1:100); ntasks = 10) do x
                sleep(0.01)
                2x
            end
            channel_map_structured!(send_endpoint, source_channel(1:100); ntasks = 10) do x
                sleep(0.01)
                2x + 1
            end
        finally
            close(send_endpoint)
        end
        results = collect(eh)
        @test all(iseven, results[1:end÷2])
        @test all(isodd, results[end÷2+1:end])
    finally
        close(eh)
    end
end

# TODO: explain the nursery passing style

# ## Error handling
#
# It is possible to satisfy the black box rule using the `Base` API:

function channel_map_base!(f, output, input; ntasks = Threads.nthreads())
    @sync for _ in 1:ntasks
        Threads.@spawn for x in input
            y = f(x)
            put!(output, y)
        end
    end
end

# However, it is problematic when `f` throws. In the above example, the
# execution will not be finished until either all items in `input` are consumed
# or all tasks throw.

function error_on_10(x)
    x == 10 && error("error in one task")
    sleep(0.01)
    return x
end

function test_channel_map_base()
    output = Channel(Inf)
    try
        channel_map_base!(error_on_10, output, source_channel(1:100); ntasks = 10)
    catch
    end
    close(output)
    results = collect(output)
    push!(results, 10)
    sort!(results)
    @test results == 1:100
end

# !!! note
#     `Base.Experimental.@sync` can be used to throw an error as soon as the
#     first task throws. However, it then leaks unfinished tasks; i.e., we can't
#     assume the black box rule anymore.
#
# ### Manual concurrent error handling is hard
#
# In general, it is hard to implement robust error handling using the `Base`
# API. Even though it is possible to do so case-by-case basis, there is no
# simple mechanism that the users can rely on.  For example, we can introduce an
# intermediate channel in the above example. This intermediate channel will be
# closed on error and hence unblock all the tasks. However, this strategy
# results in a subtle code that obscures the core logic:

function channel_map_base2!(f, output, input; ntasks = Threads.nthreads())
    tmpch = Channel() do ch
        for y in ch
            put!(output, y)
        end
    end
    try
        @sync for _ in 1:ntasks
            Threads.@spawn try
                for x in input
                    y = f(x)
                    put!(tmpch, y)
                end
            catch
                close(tmpch)
                rethrow()
            end
        end
    finally
        close(tmpch)
    end
end

function test_channel_map_base2()
    output = Channel(Inf)
    try
        channel_map_base2!(error_on_10, output, source_channel(1:100); ntasks = 10)
    catch
    end
    close(output)
    results = collect(output)
    @test length(results) < 100
end

# ### Julio automates concurrent error handling
#
# When using Julio API, errors are automatically propagated.  In fact,
# `channel_map_structured!` defined above already have the desired property:

function test_channel_map_structured_error()
    send_endpoint, eh = Julio.queue()
    try
        try
            channel_map_structured!(error_on_10, send_endpoint, source_channel(1:100); ntasks = 10)
        catch
        finally
            close(send_endpoint)
        end
        results = collect(eh)
        @test length(results) < 100
    finally
        close(eh)
    end
end

# For more detailed controll on cancellation, see also:
# [Example: bounding search results](@ref ex-bounding-search)
