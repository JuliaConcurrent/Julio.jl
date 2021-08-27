# # Selecting on custom events

# Julio.jl is built on top of Reagents.jl, a framework for writing programs with
# complex nonblocking algorithms and synchronizations.  In fact, `Julia.select`
# is a thin wrapper on top of the choice combinator `|` defined in Reagents.jl.
# Therefore, it is possible to define custom synchronization events using
# Reagents.jl API.

using Reagents
using Reagents: CAS, Computed, Return, Read, PostCommit
using Julio
using Julio: Events
using Test

# Let us define a "leaky" "broadcasting" channel; i.e., "broadcasting" in the
# sense that a `put!` can be `take!`n by multiple tasks and "leaky" in the sense
# that the items will be lost if there are no receiver tasks executing `take!`
# while the sender is executing `put!`.

struct BroadcastChannel{T,Receivers}
    eltype::Val{T}
    lck::Julio.Lock
    receivers::Receivers
end

function BroadcastChannel{T}() where {T}
    receivers = typeof(Julio.Promise{T}())[]
    lck = Julio.Lock()
    return BroadcastChannel(Val(T), lck, receivers)
end

# (We use a lock-based implementation to keep the example simple. It should also
# be possible to use some nonblocking algorithms.)
#
# The receiver requests an item simply by posting a `Julio.Promise`:
#
# (TODO: make it work without touching `Julio.Internal`)

Base.take!(bc::BroadcastChannel{T}) where {T} = Julio.Internal.apply(take!, bc)::T
function Julio.Internal.event(::typeof(take!), bc::BroadcastChannel{T}) where {T}
    (; lck, receivers) = bc
    p = Julio.Promise{T}()
    lock(lck) do
        filter!(isopen, receivers)
        push!(receivers, p)
    end
    return Reagents.WithNack() do nack
        # Cleanup in case this event is not selected:
        Reagents.dissolve(nack ⨟ PostCommit(_ -> close(p)); once = true)
        Return(nothing)
    end ⨟ Events.fetch(p)
end

# An item is sent to all the receivers registered at the time `put!` is called:

function Base.put!(bc::BroadcastChannel{T}, x) where {T}
    (; lck, receivers) = bc
    x = convert(T, x)
    lock(lck) do
        for p in receivers
            Julio.tryput!(p, x)  # tryput! instead of put! to ignore closed promises
        end
        empty!(receivers)
    end
end

#src # TODO: Running `unlock` potentially in other task is bad...?
#src function Julio.Internal.event(::typeof(put!), bc::BroadcastChannel{T}, x) where {T}
#src     (; lck, receivers) = bc
#src     x = convert(T, x)
#src     return Events.lock(lck) ⨟ PostCommit() do _
#src         for p in receivers
#src             Julio.tryput!(p, x)  # ignore closed promises
#src         end
#src         empty!(receivers)
#src         unlock(lck)
#src     end
#src end

# Demo:

function test_broadcastchannel(; ntasks = 4)
    bc = BroadcastChannel{Int}()
    done = Julio.Promise{Nothing}()
    Julio.withtaskgroup() do tg
        tasks = map(1:ntasks) do _
            Julio.spawn!(tg) do
                local items = Int[]
                while true
                    Julio.select(
                        (fetch, done) => Returns(true),
                        (take!, bc) => x -> begin
                            push!(items, x)
                            false
                        end,
                    ) && break
                end
                return items
            end
        end
        try
            for x in 1:2^10
                put!(bc, x)
            end
        finally
            done[] = nothing
        end
        for t in tasks
            items = fetch(t)
            @test all(>(0), diff(items))
        end
        return map(length ∘ fetch, tasks)  #src
    end
end
