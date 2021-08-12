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
        A channel can be created using `Julio.channel`. It returns the "handles"
        for input (sender) and output (receiver).
        =#
        input_handle, output_handle = Julio.channel()
        #=
        Both ends of the channel must be `open`ed before using it.
        =#
        open(output_handle) do output_endpoint
            #=
            Furthermore, when shared across multiple tasks, the channel must be
            opened before spawn and closed inside the task.  The channel must be
            opened before spawn to avoid the race condition; i.e., if it were
            opened inside a task, the other endpoint may be accessed before the
            task starts.  The channel has to be closed to unblock other
            endpoints.
            =#
            let input_endpoint = open(input_handle)  # open before spawn
                Julio.spawn!(tg) do
                    try
                        for i in 1:10
                            put!(input_endpoint, i)
                        end
                    finally
                        close(input_endpoint)  # close inside the child task
                    end
                end
            end

            #=
            Observe that both input and ouptut handles are opened above before
            the first `spawn!`. This is required when using unbuffered channel.

            The following `collect(output_endpoint)` continues until the child
            task calls `close(input_endpoint)`.
            =#
            @test collect(output_endpoint) == 1:10
        end
        #=
        ---
        =#
    end
end

# The above pattern is very flexible but rather too verbose.  To make it more
# concise, `Julio.spawn!` automates the above pattern.

function test_channel_open_on_spawn()
    Julio.withtaskgroup() do tg
        input_handle, output_handle = Julio.channel()
        open(output_handle) do output_endpoint

            #=
            "Resource handles" passed to `Julia.spawn!` are automatically opened
            just before spawning the task and closed when the task ends:
            =#
            Julio.spawn!(tg, input_handle) do input_endpoint
                for i in 1:10
                    put!(input_endpoint, i)
                end
            end
            #=
            ---
            =#

            @test collect(output_endpoint) == 1:10
        end
    end
end

# The input and output handles can be opened multiple times.  The handle is
# considered closed when all opened endpoints  are closed.

function test_channel_open_many()
    Julio.withtaskgroup() do tg
        input_handle, output_handle = Julio.channel()
        open(output_handle) do output_endpoint

            Julio.spawn!(tg, input_handle) do input_endpoint
                put!(input_endpoint, 1)
            end
            Julio.spawn!(tg, input_handle) do input_endpoint
                put!(input_endpoint, 2)
            end
            Julio.spawn!(tg, input_handle) do input_endpoint
                put!(input_endpoint, 3)
            end

            @test sort!(collect(output_endpoint)) == 1:3
        end
    end
end

# Another approach for opening and closing the channel is to use one task group
# for each endpoint:

function test_channel_open_many_scoped()
    input_handle, output_handle = Julio.channel()
    open(output_handle) do output_endpoint
        local task
        Julio.withtaskgroup() do tg0
            open(input_handle) do input_endpoint
                task = Julio.spawn!(tg0) do
                    sort!(collect(output_endpoint))
                end
                Julio.withtaskgroup() do tg1
                    for i in 1:10
                        Julio.spawn!(tg1) do
                            put!(input_endpoint, i)
                        end
                    end
                end
            end
        end
        @test fetch(task) == 1:10
    end
end

# Note:
#
# * The "consumer" task running `sort!(collect(output_endpoint))` must be
#   spawned inside the `open(input_handle) do` block. Otherwise, there may be no
#   writer when `collect` is started. If there is no writer, `output_endpoint`
#   is treated as empty.
#
# * The "producer" task group `tg1` should be inside of the `open(input_handle)
#   do` block in this style since we cannot close the channel until all the
#   tasks using it finish.
#
# * The "consumer" task group `tg0` should be *outside* of the
#   `open(input_handle) do` block since `close` on `input_handle` stops the
#   iteration of `output_endpoint`.
#
# Although this example shows that the scope-based resource handling (`open(...)
# do` etc.) plays nicely with `Julio.withtaskgroup`, it's easier to let
# `Julio.spawn!` open the resource (if supported) as shown in the earlier
# examples.

# When it is not required or desired to associate the scopes and the resources
# (e.g., the channel is not used for signaling the end of the processing)
# `Julio.openchannel` can be used.

function test_openchannel()
    input_endpoint, output_endpoint = Julio.openchannel()
    Julio.withtaskgroup() do tg
        Julio.spawn!(tg) do
            put!(input_endpoint, 111)
        end
        @test take!(output_endpoint) == 111
    end
end

# Note that `Julio.channel` is always unbuffered. Use `Julio.queue` and
# `Julio.stack` for buffered channels.

function test_openqueue()
    input_endpoint, output_endpoint = Julio.openqueue()
    put!(input_endpoint, 111)
    put!(input_endpoint, 222)
    @test take!(output_endpoint) == 111
    @test take!(output_endpoint) == 222
end

# ## Timeout
#
# Julio can introduce a timeout for arbitrary code blocks.  The timeout is
# triggered whenever the code is blocked by a Julia API.

function test_timeout()
    input_handle, output_handle = Julio.queue()
    open(input_handle) do input_endpoint
        Julio.withtimeout(0.1) do
            put!(input_endpoint, nothing)  # never completes
        end
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
    input_handle, output_handle = Julio.channel()
    open(output_handle) do output_endpoint
        task = nothing
        err = try
            Julio.withtaskgroup() do tg
                task = Julio.spawn!(tg, input_handle) do input_endpoint
                    produce!(input_endpoint)
                end
                for i in 1:3
                    @test take!(output_endpoint) == i
                end
                error("cancel")
            end
            nothing
        catch err
            err
        end
        @test err isa Exception
        @test istaskdone(task)
    end
end

# ## [Manual cancellation](@id man-cancel-scope)
#
# ### Cancel scope
#
# Cancellation of Julio tasks can also be triggered manually.

function test_cancel_scope()
    _, output_endpoint = Julio.openchannel()
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
                take!(output_endpoint)  # blocks
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
                    take!(output_endpoint)  # blocks
                end
                take!(output_endpoint)  # blocks
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
        `take!(output_endpoint)`, this code reliably synchronizes all sub-tasks.
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
        ie1, oe1 = Julio.openchannel()
        ie2, oe2 = Julio.openchannel()
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
