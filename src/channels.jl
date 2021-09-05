struct AlwaysEmpty{T} end
Base.eltype(::Type{AlwaysEmpty{T}}) where {T} = T
Base.isempty(::AlwaysEmpty) = true
putting(::AlwaysEmpty) = Return(Block())
taking(::AlwaysEmpty) = Return(Block())

abstract type ChannelEndpoint{T} end
Base.eltype(::Type{ChannelEndpoint{T}}) where {T} = T
ContextManagers.maybeenter(ch::ChannelEndpoint) = ch

struct SendEndpoint{T,Data,Send} <: ChannelEndpoint{T}
    eltype::Val{T}
    data::Data
    send::Send
    senderclosed::typeof(Promise{Nothing}())
    receiverclosed::typeof(Promise{Nothing}())
end

struct ReceiveEndpoint{T,Data,Receive} <: ChannelEndpoint{T}
    eltype::Val{T}
    data::Data
    receive::Receive
    senderclosed::typeof(Promise{Nothing}())
    receiverclosed::typeof(Promise{Nothing}())
end

function channel_endpoints(data)
    send, receive = Reagents.channel(eltype(data), Nothing)
    senderclosed = Promise{Nothing}()
    receiverclosed = Promise{Nothing}()
    return (
        SendEndpoint(Val(eltype(data)), data, send, senderclosed, receiverclosed),
        ReceiveEndpoint(Val(eltype(data)), data, receive, senderclosed, receiverclosed),
    )
end

Julio.channel(T::Type = Any) = channel_endpoints(AlwaysEmpty{T}())
Julio.stack(T::Type = Any) = channel_endpoints(TreiberStack{T}())
Julio.queue(T::Type = Any) = channel_endpoints(MSQueue{T}())

selfclosed(sept::SendEndpoint) = sept.senderclosed
dualclosed(sept::SendEndpoint) = sept.receiverclosed
selfclosed(rept::ReceiveEndpoint) = rept.receiverclosed
dualclosed(rept::ReceiveEndpoint) = rept.senderclosed

struct NoInput <: Exception end
struct NoReceivers <: Exception end

function tryputting(sept::SendEndpoint)
    (; send, data, receiverclosed) = sept
    if istracing()
        post_send = PostCommit(_ -> @trace(label = :putting_br_send))
        post_data = PostCommit(_ -> @trace(label = :putting_br_data))
    else
        post_send = Identity()
        post_data = Identity()
    end
    return (
        (send ⨟ Return(true) ⨟ post_send) |
        # TODO: check `receiverclosed` in a non-blocking manner before `putting(data)`?
        (putting(data) ⨟ post_data ⨟ Return(true)) |
        (fetching(receiverclosed) ⨟ Return(false))
    )
end

putting(sept::SendEndpoint) =
    tryputting(sept) ⨟ Map(x -> x ? nothing : Error(NoReceivers()))

block_if_nonempty(data) = Computed(x -> isempty(data) ? Return(x) : Block())

function maybetaking(rept::ReceiveEndpoint)
    (; receive, data, senderclosed) = rept
    item = Return(nothing) ⨟ (receive ⨟ block_if_nonempty(data) | taking(data)) ⨟ Map(Some)
    # recheck = item | Return(Error(NoInput()))
    # recheck = ReturnIfBlocked(Error(NoInput())) ⨟ item
    # recheck = Return(Error(NoInput()))
    recheck = taking(data) ⨟ Map(Some) | Return(nothing)
    return item | fetching(senderclosed) ⨟ Return(nothing) ⨟ recheck
end

taking(rept::ReceiveEndpoint) =
    maybetaking(rept) ⨟ Map(x -> x === nothing ? Error(NoInput()) : x)

function Base.close(ept::ChannelEndpoint)
    @trace(label = :close_start, issend = ept isa SendEndpoint)
    wasclosed = event(Julio.tryput!, selfclosed(ept), nothing)()
    @trace(label = :close_done, issend = ept isa SendEndpoint, wasclosed)
    return
end

event(::typeof(put!), sept::SendEndpoint, x) =
    Return(convert(eltype(sept), x)) ⨟ putting(sept)
event(::typeof(push!), sept::SendEndpoint) = event(put!, sept, x)

function Base.put!(sept::SendEndpoint, x)
    @trace label = :put_start x
    apply(put!, sept, x)
    @trace label = :put_done
    return
end

event(::typeof(Julio.maybetake!), rept::ReceiveEndpoint) = maybetaking(rept)
Julio.maybetake!(rept::ReceiveEndpoint) = apply(Julio.maybetake!, rept)

event(::typeof(take!), rept::ReceiveEndpoint) = taking(rept)

function Base.take!(rept::ReceiveEndpoint)
    @trace label = :take_start
    ans = apply(take!, rept)
    @trace label = :take_done x = ans
    return ans
end

function Base.push!(sept::SendEndpoint, x)
    put!(sept, x)
    return sept
end

Base.IteratorSize(::Type{<:ReceiveEndpoint}) = Base.SizeUnknown()

function Base.iterate(rept::ReceiveEndpoint, ::Nothing = nothing)
    @trace label = :iterate_start
    x = cancellable_react!(taking(rept))
    @trace label = :iterate_done ans = x
    if x === Error(NoInput())
        return nothing
    else
        return (something(x), nothing)
    end
end

function on_channel_handle_method_error(io::IO, exc::MethodError, argtypes, _kwargs)
    @nospecialize argtypes _kwargs
    putfns = (put!, Julio.tryput!)
    takefns = (take!, Julio.maybetake!)
    length(argtypes) > 0 || return
    EndpointType = argtypes[1]::Type
    if (
        (EndpointType <: ReceiveEndpoint && exc.f in putfns) ||
        (EndpointType <: SendEndpoint && exc.f in takefns)
    )
        required = exc.f in putfns ? "input" : "output"
        given = required == "input" ? "output" : "input"
        println(io)
        printstyled(io, string(exc.f); color = :cyan)
        print(io, " requires an ")
        printstyled(io, "$required endpoint"; color = :cyan, bold = true)
        print(io, " not an ")
        printstyled(io, "$given endpoint"; color = :cyan)
        print(io, ". ")
        print(
            io,
            """
            Use the other endpoint. For example:

                send_endpoint, receive_endpoint = Julio.channel()
                $(exc.f)($(required)_endpoint$(exc.f in putfns ? ", item" : ""))

            """,
        )
        println(io)
    end
end
