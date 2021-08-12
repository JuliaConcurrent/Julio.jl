"""
    Blocking(data_collection)

A very minimalistic implementation of blocking collection. It is used in
`TaskGroup`.

(TODO: use channel in `TaskGroup`?)
"""
struct Blocking{T,Data,Send,Receive}
    eltype::Val{T}
    data::Data          # holds value of type T
    send::Send          # swaps value::T -> nothing
    receive::Receive    # swaps nothing -> value::T
end

function Blocking(data)
    send, receive = Reagents.channel(eltype(data), Nothing)
    return Blocking(Val(eltype(data)), data, send, receive)
end

Base.eltype(::Type{<:Blocking{T}}) where {T} = T

# Note: these are not quite enough for ordering guarantee; see `block_if_nonempty`
putting(b::Blocking) = b.send | putting(b.data)
taking(b::Blocking) = b.receive | taking(b.data)

Base.put!(b::Blocking, x) = putting(b)(convert(eltype(b), x))
Base.take!(b::Blocking) = taking(b)()

blocknothing() = Map(x -> x === nothing ? Block() : something(x))

putting(c::TreiberStack) = pushing(c)
taking(c::TreiberStack) = trypopping(c) ⨟ blocknothing()

putting(c::MSQueue) = pushing(c)
taking(c::MSQueue) = trypoppingfirst(c) ⨟ blocknothing()

blocking_treiberstack(T) = Blocking(TreiberStack{T}())
