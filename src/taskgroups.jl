mutable struct TaskGroup
    tasks::typeof(blocking_treiberstack(Task))
    scope::CancelScope
    error::Union{Nothing,CompositeException}
end

TaskGroup(scope::CancelScope) = TaskGroup(blocking_treiberstack(Task), scope, nothing)

Julio.cancel!(tg::TaskGroup) = Julio.cancel!(tg.scope)

function Julio.cancel!(scope::CancelScope)
    Julio.cancel!(scope.token)
    handle = @something(scope.dissolvehandle, return)
    Reagents.clear!(handle)
    return
end

function Julio.cancelscope()
    token = cancellation_token()
    handle = Julio.oncancel(Julio.cancel!, token)
    return CancelScope(token, handle)
end

function Julio.withtaskgroup(f::F, scope::CancelScope = Julio.cancelscope()) where {F}
    maindone = Promise{Nothing}()
    tg = TaskGroup(scope)
    token = tg.scope.token
    with_context(CANCELLATION_TOKEN => token) do
        waiter = Threads.@spawn waitall!(tg, maindone, token)
        local ans
        try
            try
                ans = f(tg)
            finally
                put_nocancel!(maindone, nothing)
            end
            wait(waiter)
        catch err
            Julio.cancel!(token)
            @debug(
                "`withtaskgroup`",
                exception = (err, catch_backtrace()),
                current_task(),
                iscancelled(err),
            )
            istaskdone(waiter) || wait(waiter)  # avoid throwing twice from `manager`
            if tg.error === nothing
                iscancelled(err) || rethrow()
                return
            else
                iscancelled(err) || pushfirst!(tg.error.exceptions, err)
                throw(tg.error)
            end
        finally
            handle = tg.scope.dissolvehandle
            if handle isa DissolveHandle
                Reagents.clear!(tg.scope.dissolvehandle)
            end
        end
        @assert istaskdone(waiter)
        tg.error === nothing || throw(tg.error)
        return ans
    end
end

function iscancelled(@nospecialize(err))
    if err isa Cancelled
        return true
    elseif err isa TaskFailedException
        return iscancelled(err.task.result)
    elseif err isa CompositeException
        return all(iscancelled, err)
    end
    return false
end

"""
`waitall!` is the "background" child task manager.  It handles child task
completion without waiting for the completion of the main body of
`Julio.withtaskgroup`, to clearing `tg.tasks` as soon as possible.

TODO: Instead of this task manager, let the child task proactively cleanup the
parent-to-child reference. This task manager style of cleaning things up have a
disadvantage that it can only be cleaned up in the "container order" of
`tg.tasks`. This is bad for server-like use case where the number of child task
is unbounded.
"""
function waitall!(tg::TaskGroup, maindone::Promise{Nothing}, token::CancellationTokenType)
    function _wait(task::Task)
        @trace label = :wait task
        try
            wait(task)
        catch err
            # @info "Got an error" repr(err) iscancelled(err)
            iscancelled(err) && return
            Julio.cancel!(token)
            if tg.error === nothing
                cex = tg.error = CompositeException()
            else
                cex = tg.error
            end
            push!(cex, err)
        end
    end

    # @info "phase 1 start"
    @trace label = :waitall_start stack = tg.tasks.data.head[]
    while true
        t = @something((taking(tg.tasks) | _fetching(maindone))(), break)
        # @info "waiting" repr(t)
        _wait(t)
        # @info "done waiting" repr(t)
    end
    @trace label = :waitall_phase1_done stack = tg.tasks.data.head[]
    # @info "phase 1 done"
    # @info "phase 2 start"

    @assert _fetching(maindone)() === nothing
    # The body of `withtaskgroup` is done. We now only need to process
    # `tg.tasks` until it's emptied.
    while true
        t = @something(Reagents.trysync!(taking(tg.tasks)), break)
        _wait(t)
    end
    # @info "phase 2 done"
    @trace label = :waitall_phase2_done
end

function Julio.spawn!(@nospecialize(f), tg::TaskGroup, args...)
    token = tg.scope.token

    # Auto-open ("bind") resources to this task.
    contexts = []
    opened_args = map(args) do x
        c = @something(ContextManagers.maybeenter(x), return x)
        push!(contexts, c)
        return ContextManagers.value(c)
    end

    function spawn_wrapper()
        try
            # Since taskgroup may not be nested, we need to reset the dynamic
            # scope context:
            apply_f_args() = f(opened_args...)
            ans = with_context(apply_f_args, CANCELLATION_TOKEN => token)
            while !isempty(contexts)
                ContextManagers.exit(pop!(contexts))
            end
            ans
        catch err
            @debug(
                "`spawn_wrapper`",
                exception = (err, catch_backtrace()),
                current_task(),
                iscancelled(err),
                f,
            )
            Julio.cancel!(token)
            while !isempty(contexts)
                try
                    ContextManagers.exit(pop!(contexts), err)
                catch
                end
            end
            rethrow()
        end
    end
    task = Task(spawn_wrapper)
    task.sticky = false
    schedule(task)
    put!(tg.tasks, task)
    @trace label = :scheduled task
    return task
end

is_token_cancelled(token) = something(maybefetching(token)()) isa Some{Cancelled}

Julio.iscancelled() = is_token_cancelled(@something(CANCELLATION_TOKEN[], return false))

function Julio.checkpoint()
    token = @something(CANCELLATION_TOKEN[], return)
    ans = @something(Reagents.try!(_fetching(token)), return)
    # Occasionally try sync? Maybe not useful?
    # ans = @something(Reagents.trysync!(fetching(token)), return)
    ans isa Cancelled && throw(ans)
    return
end

function Julio.yield()
    Julio.checkpoint()
    yield()
end
