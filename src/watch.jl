# Initially inspired by `tokio::sync::watch`
# https://docs.rs/tokio/1.10.0/tokio/sync/watch/index.html
# but included the `predicate` and make it level-triggered ("sticky").
struct WatchFor{T,P,Value<:Reagents.Ref{T}}
    predicate::P
    value::Value
    send::typeof(Reagents.channel(Nothing)[1])
    receive::typeof(Reagents.channel(Nothing)[2])
end

function WatchFor{T}(predicate, state) where {T}
    state = convert(T, state)
    send, receive = Reagents.channel(Nothing)
    return WatchFor(predicate, Reagents.Ref{T}(state), send, receive)
end

"""
    fetching(w::WatchFor{T}) :: Reagent of _ → T
"""
function fetching(w::WatchFor)
    function fetch_waitfor(_)
        state = w.value[]
        if w.predicate(state)
            return Return(state)
        else
            return Return(nothing) ⨟ w.receive ⨟ Read(w.value)
        end
    end
    return Computed(fetch_waitfor)
end

"""
    updating(updater, w::WatchFor{T}) :: Reagent of X → Nothing
where
    updater :: (state::T, input::X) ↦ newstate::T
"""
function updating(updater, w::WatchFor)
    return Computed() do input
        state = w.value[]
        newstate = updater(state, input)
        cas = CAS(w.value, state, newstate)
        if w.predicate(newstate)
            return cas ⨟ PostCommit() do _
                Reagents.dissolve(w.send)
            end
        else
            return cas
        end
    end
end
