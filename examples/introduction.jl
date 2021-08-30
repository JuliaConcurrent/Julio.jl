# # Introduction to Julio

using Julio
using Test

# (Note: Currently there's no macro-based syntactic sugar. This is for making
# sure all the components are composable during the design process.)

# ## Tasks and task groups
#
# Julio manages tasks in *task groups*. Spawning a task requires creating a task
# group first.

function test_simple_spawn()
    Julio.withtaskgroup() do tg
        task = Julio.spawn!(tg) do
            3 + 4
        end
        @test (1 + 2) + fetch(task) == 10
    end
end

# This style is useful when combined with the resource management using the
# `open(...) do` idiom (scope-based resource management).  See [black box
# rule](@id black-box) for more information.

# ## Channels

function test_channel_verbose()
    Julio.withtaskgroup() do tg
        #=
        A channel can be created using `Julio.channel`. It returns the
        *endpoints* for the send and receive sides.
        =#
        send_endpoint, receive_endpoint = Julio.channel()

        #=
        The `send_endpoint` supports `put!` function. It can be called from
        arbitrary tasks safely.
        =#
        Julio.spawn!(tg) do
            try
                for i in 1:10
                    put!(send_endpoint, i)
                end
            finally
                close(send_endpoint)  # signaling that there are no more items
            end
        end

        #=
        The `receive_endpoint` supports `take!`. It also supports the iteration
        protocol.  The following `collect(receive_endpoint)` continues until the
        child task calls `close(send_endpoint)`.
        =#
        try
            @test collect(receive_endpoint) == 1:10
        finally
            close(receive_endpoint)  # signaling the child task if something went wrong
        end
        #=
        ---
        =#
    end
end

# Use a task group to wait for multiple tasks before closing the endpoint:

function test_channel_open_many_scoped()
    send_endpoint, receive_endpoint = Julio.channel()
    local task
    Julio.withtaskgroup() do tg0
        task = Julio.spawn!(tg0) do
            try
                sort!(collect(receive_endpoint))
            finally
                close(receive_endpoint)
            end
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
end

# Note that `Julio.channel` is always unbuffered. Use `Julio.queue` and
# `Julio.stack` for buffered channels.

function test_queue()
    send_endpoint, receive_endpoint = Julio.queue()
    put!(send_endpoint, 111)
    put!(send_endpoint, 222)
    @test take!(receive_endpoint) == 111
    @test take!(receive_endpoint) == 222
end

# ## Timeout
#
# Julio can introduce a timeout for arbitrary code blocks.  The timeout is
# triggered whenever the code is blocked by a Julia API.

function test_timeout()
    send_endpoint, receive_endpoint = Julio.channel()
    Julio.withtimeout(0.1) do
        put!(send_endpoint, nothing)  # never completes
    end
end

# ## Automatic cancellation
#
# Julio cancells the tasks within the same task group if one of them (including
# the parent task) throws an exception.

function produce!(input)
    i = 0
    while true
        i += 1
        put!(input, i)
    end
end

function test_cancellation()
    send_endpoint, receive_endpoint = Julio.channel()
    try
        task = nothing
        err = try
            Julio.withtaskgroup() do tg
                task = Julio.spawn!(tg) do
                    try
                        produce!(send_endpoint)
                    finally
                        close(send_endpoint)
                    end
                end
                for i in 1:3
                    @test take!(receive_endpoint) == i
                end
                error("cancel")
            end
            nothing
        catch err
            err
        end
        @test err isa Exception
        @test istaskdone(task)
    finally
        close(receive_endpoint)
    end
end

# ## [Manual cancellation](@id man-cancel-scope)
#
# ### Cancel scope
#
# Cancellation of Julio tasks can also be triggered manually.

function test_cancel_scope()
    _, receive_endpoint = Julio.channel()
    #=
    The parts of code that are cancelled together can be managed by
    `Julio.cancelscope`:
    =#
    scope = Julio.cancelscope()
    #=
    Let's see how it works with a nested task tree:
    =#
    Julio.withtaskgroup() do tg0
        Julio.spawn!(tg0) do
            #=
            The cancel scope can be installed at different places.  For example,
            it can be manually `open`ed.  The blocking calls inside the `do`
            block now checks the cancellation signal whenever Julio's blocking
            method is invoked.
            =#
            open(scope) do
                take!(receive_endpoint)  # blocks
            end
            #=
            ---
            =#
        end  # Julio.spawn!(tg0) do
        Julio.spawn!(tg0) do
            #=
            The cancel scope can be also be passed to `Julio.withtaskgroup` to
            associate the cancellation scope to the tasks managed by it.
            =#
            Julio.withtaskgroup(scope) do tg1
                Julio.spawn!(tg1) do
                    take!(receive_endpoint)  # blocks
                end
                take!(receive_endpoint)  # blocks
            end
            #=
            ---
            =#
        end  # Julio.spawn!(tg0) do
        #=
        Cancellation can be triggered by `Julio.cancel!`.
        =#
        Julio.cancel!(scope)
        #=
        Since the cancellation signal unblocks all the blocking calls
        `take!(receive_endpoint)`, this code reliably synchronizes all
        sub-tasks.
        =#
    end  # Julio.withtaskgroup() do tg0
end

# ### Interop with other cancellation mechanisms
#
# Julio can be used with other cancellation mechanisms. For example, several
# `Base` API supports cancellation by concurrent `close` on a "resource" object
# (e.g., `Base.Channel`, `Timer`, files). We can hook the `close` call into
# Julio's cancellation token by calling `Julio.onclose(close, resource)`.

function test_cancel_interop()
    result = @timed try
        Julio.withtaskgroup() do tg
            Julio.spawn!(tg) do
                timer = Timer(60)
                Julio.oncancel(close, timer)  # call `close(timer)` on cancellation
                wait(timer)  # this can be interrupted by `close(timer)`
            end
            error("cancelling")
        end
        false
    catch
        true
    end
    @test result.value  # terminated by the execption
    @test result.time < 30  # it didn't wait 60 seconds
end

# ## Event selection
#
# Julio supports executing one (and exactly one) of synchronizable *events*.
# Here, an event means a possibly blocking operations such as taking an item
# from a channel.

function test_select()
    Julio.withtaskgroup() do tg
        #=
        Suppose that we have two channels, but only one of them are available:
        =#
        ie1, oe1 = Julio.channel()
        ie2, oe2 = Julio.channel()
        Julio.spawn!(tg) do
            put!(ie1, 111)
        end

        #=
        We can select an available "event" (here, `take!`) using `Julio.select`
        function.
        =#
        selected = nothing
        Julio.select(
            (take!, oe1) => item -> begin
                selected = item  # result of `take!(oe1)`
            end,
            (take!, oe2) => item -> begin
                selected = item  # result of `take!(oe2)` (unreachable)
            end,
        )
        #=
        Since only `oe1` has a task at the input endpoint, `take!(oe1)` is
        chosen:
        =#
        @test selected == 111
        #=
        ---
        =#
    end
end

# Note that `Julio.select` works for various synchronizable events and not just
# channels.  See [select](@ref man-select) for more information.
