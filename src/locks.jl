struct Lock <: Base.AbstractLock
    owner::typeof(Reagents.Ref{Union{Nothing,Task}}())
    notify::typeof(Reagents.channel(Nothing)[1])
    wait::typeof(Reagents.channel(Nothing)[2])
    depth::typeof(Reagents.Ref{Int}())
end

function Lock()
    notify, wait = Reagents.channel(Nothing)
    return Lock(
        Reagents.Ref{Union{Nothing,Task}}(nothing),
        notify,
        wait,
        Reagents.Ref{Int}(0),
    )
end

event(::typeof(lock), l::Lock, requester::Task = current_task()) =
    Computed() do _
        owner = l.owner[]
        @trace(
            label = :locking,
            ownerid = owner === nothing ? UInt(0) : taskid(owner),
            requesterid = taskid(requester),
        )
        if owner === requester
            # Note: Since the increment for `l.depth` can be executed on any
            # task if there is a downstream `Swap` reagent, we need to
            # simultaneously verify that `l.owner[]` is not changed.
            d = l.depth[]
            return CAS(l.owner, owner, owner) ⨟ CAS(l.depth, d, d + 1) ⨟ PostCommit() do _
                @trace(label = :locked_rec, requesterid = taskid(requester))
            end
        end
        cas = CAS(l.owner, nothing, requester)
        if owner === nothing
            return cas
        else
            return (l.wait ⨟ cas | Map(_ -> l.owner[] === nothing ? Retry() : Block()))
        end
    end

function Base.lock(l::Lock)
    apply(lock, l)
    owner = l.owner[]
    @trace(label = :locked_base, ownerid = owner === nothing ? UInt(0) : taskid(owner))
    @assert owner === current_task()
    return
end
Base.trylock(l::Lock) = Reagents.try!(event(lock, l)) !== nothing

function Base.unlock(l::Lock)
    owner = l.owner[]
    @trace(label = :unlock, ownerid = owner === nothing ? UInt(0) : taskid(owner))
    @assert owner === current_task()
    if l.depth[] > 0
        l.depth[] -= 1
        return
    end
    l.owner[] = nothing
    Reagents.trysync!(l.notify)
    return
end
