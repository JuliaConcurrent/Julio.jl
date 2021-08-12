# We store the state of `Promise` in a single `Ref` by using the `Union` type.

struct Closed end

const PromiseRef{T} = Reagents.Ref{Union{
    Nothing,  # indicates the value is not set and the promise is not closed
    Some{T},  # indicates that the value of type `T` is set
    Closed,   # indicates that the promise is closed
}}

# The `Promise` type also contains a channel for sending and receiving signals
# on the state change:

struct Promise{T,Ref<:PromiseRef{T}}
    value::Ref
    send::typeof(Reagents.channel(Nothing)[1])
    receive::typeof(Reagents.channel(Nothing)[2])
end

Promise() = Promise{Any}()
function Promise{T}() where {T}
    send, receive = Reagents.channel(Nothing)
    return Promise(PromiseRef{T}(nothing), send, receive)
end

# Since setting value and closing the channel are similar, we define an internal
# function that tries to set `p.value::Reagents.Ref` if it's not already set and
# then, upon success, notify all the waiters:

tryputting_internal(p::Promise) =
    Computed() do x
        CAS(p.value, nothing, x) ⨟ Return(Some(x))
    end ⨟ PostCommit() do _
        while Reagents.trysync!(p.send) !== nothing
        end
    end | Return(nothing)

# Then, we can define a reagent for setting a value and a reagent for closing
# the promise as simple wrappers:

tryputting(p::Promise{T}) where {T} = Map(Some{T}) ⨟ tryputting_internal(p)
closing(p::Promise) = Return(Closed()) ⨟ tryputting_internal(p)

# The reagent for fetching the promise needs to first listen to the putting and
# closing events (to avoid missing the notification) and *then* check if the
# value is set:

struct PromiseClosedError <: Exception
    promise::Promise
end

fetching(p::Promise{T}) where {T} =
    (
        (Return(nothing) ⨟ p.receive ⨟ Read(p.value)) |
        (Read(p.value) ⨟ Map(x -> x === nothing ? Block() : x))
    ) ⨟ Map(x -> x isa Closed ? PromiseClosedError(p) : something(x))

maybefetching(p::Promise{T}) where {T} = Read(p.value) ⨟ Map() do x
    if x isa Closed
        PromiseClosedError(p)
    else
        x
    end
end

# We check the returned value of `fetching` outside reagent. If it is the
# `Closed` sentinel value, the exception is thrown:

# It is now straightforward to define the API mentioned above:

event(::typeof(fetch), p::Promise) = fetching(p)

Base.fetch(p::Promise) = apply(fetch, p)
Base.getindex(p::Promise) = fetch(p)

event(::typeof(Julio.maybefetch), p::Promise) = maybefetching(p)
Julio.maybefetch(p) = apply(Julio.maybefetch, p)

Base.close(p::Promise) = closing(p)()
Base.isopen(p::Promise) = !(p.value[] isa Closed)

event(::typeof(put!), p::Promise{T}, x) where {T} =
    Return(Some{T}(x)) ⨟
    tryputting_internal(p) ⨟ # -> Union{Some{_}, Nothing}
    Map() do x
        if x === nothing
            if p.value[] isa Closed
                Error(PromiseClosedError(p))
            else
                Error(ErrorException("promise already has a value"))
            end
        else
            nothing  # TODO: what's the appropriate returned value?
        end
    end

Base.put!(p::Promise, x) = apply(put!, p, x)
Base.setindex!(p::Promise, x) = put!(p, x)

event(::typeof(Julio.tryput!), p::Promise{T}, x) where {T} =
    Return(Some{T}(x)) ⨟ tryputting_internal(p) ⨟ Map(!isnothing)
Julio.tryput!(p::Promise, x) = apply(Julio.tryput!, p, x)

"""
    put_nocancel!(p::Promise, x)

Just like `put!` but it works after cancellation.
"""
put_nocancel!(p::Promise, x) = handle_result(event(put!, p, x)())
