struct AlwaysEmpty{T} end
Base.eltype(::Type{AlwaysEmpty{T}}) where {T} = T
Base.isempty(::AlwaysEmpty) = true
putting(::AlwaysEmpty) = Return(Block())
taking(::AlwaysEmpty) = Return(Block())

# The channel API is inspired by Trio.
#
# * Separating input/output endpoints is nice for separately closing the input
#   or output end. (Closing output is a no-op ATM.)
# * Tracking the number of input/output endpoints is nice for automating when
#   to close the channel.
#
# A major difference to Trio's API is that Julio first creates resource handles
# which then has to be opened before using them as channel endpoints. This is
# different from Trio's channel which starts as "open" state. Cloning the
# channel also acts as "opening" the channel. It is somewhat unsatisfactory in
# that the resource is already opened before the `with` statement (although it's
# the case for other resource objects such as files in Python).
#
# It looks like separating resource handle does not complicate the code much
# since `spawn!` automates clone+close. However, Julio's API is somewhat easier
# to write racy code (by start accessing when other endpoint hasn't been opened
# yet). This is in contrast to Trio's API which is easier to write deadlock (by
# forgetting to close the channel). This may indicate Trio's approach is better,
# since it is easy to recover from deadlock (e.g., use timeout in unit tests)
# when we have the cancellation mechanisms. On the other hand, reproducing races
# is hard.
#
# Note that `Julio.withchannel` etc. can be used as Trio-like API where the
# channel starts at open state. Maybe it's better to keep both APIs for now and
# then see which one is easier to use in practice.
#
# See: [Fine-tuning channels · Issue #719 ·
# python-trio/trio](https://github.com/python-trio/trio/issues/719)

abstract type ChannelHandle{T} <: Resource end

counter() = WatchFor{Int}(iszero, 0)

struct InputHandle{T,Data,Send} <: ChannelHandle{T}
    eltype::Val{T}
    data::Data
    send::Send
    nsenders::typeof(counter())
    nreceivers::typeof(counter())
end

struct OutputHandle{T,Data,Receive} <: ChannelHandle{T}
    eltype::Val{T}
    data::Data
    receive::Receive
    nsenders::typeof(counter())
    nreceivers::typeof(counter())
end

abstract type Endpoint{T} end
Base.eltype(::Type{Endpoint{T}}) where {T} = T

struct InputEndpoint{T,Handle<:InputHandle{T}} <: Endpoint{T}
    handle::Handle
    closed::Threads.Atomic{Bool}
end

struct OutputEndpoint{T,Handle<:OutputHandle{T}} <: Endpoint{T}
    handle::Handle
    closed::Threads.Atomic{Bool}
end

function blocking_handles(data)
    send, receive = Reagents.channel(eltype(data), Nothing)
    nsenders = counter()
    nreceivers = counter()
    return (
        InputHandle(Val(eltype(data)), data, send, nsenders, nreceivers),
        OutputHandle(Val(eltype(data)), data, receive, nsenders, nreceivers),
    )
end

Julio.channel(T::Type = Any) = blocking_handles(AlwaysEmpty{T}())
Julio.stack(T::Type = Any) = blocking_handles(TreiberStack{T}())
Julio.queue(T::Type = Any) = blocking_handles(MSQueue{T}())

selfcounter(ih::InputHandle) = ih.nsenders
dualcounter(ih::InputHandle) = ih.nreceivers
selfcounter(oh::OutputHandle) = oh.nreceivers
dualcounter(oh::OutputHandle) = oh.nsenders
selfcounter(ep::Endpoint) = selfcounter(ep.handle)
dualcounter(ep::Endpoint) = dualcounter(ep.handle)

add!(w::WatchFor, x) = updating(+, w)(x)

struct NoInput <: Exception end
struct NoReceivers <: Exception end

function tryputting(ie::InputEndpoint)
    (; send, data, nreceivers) = ie.handle
    if istracing()
        post_send = PostCommit(_ -> @trace(label = :putting_br_send))
        post_data = PostCommit(_ -> @trace(label = :putting_br_data))
    else
        post_send = Identity()
        post_data = Identity()
    end
    return (
        (send ⨟ Return(true) ⨟ post_send) |
        (putting(data) ⨟ post_data ⨟ Return(true)) |
        (fetching(nreceivers) ⨟ Return(false))
    )
end

putting(ie::InputEndpoint) = tryputting(ie) ⨟ Map(x -> x ? nothing : Error(NoReceivers()))

block_if_nonempty(data) = Computed(x -> isempty(data) ? Return(x) : Block())

function maybetaking(oe::OutputEndpoint)
    (; receive, data, nsenders) = oe.handle
    item = Return(nothing) ⨟ (receive ⨟ block_if_nonempty(data) | taking(data)) ⨟ Map(Some)
    # recheck = item | Return(Error(NoInput()))
    # recheck = ReturnIfBlocked(Error(NoInput())) ⨟ item
    # recheck = Return(Error(NoInput()))
    recheck = taking(data) ⨟ Map(Some) | Return(nothing)
    return item | fetching(nsenders) ⨟ Return(nothing) ⨟ recheck
end

taking(oe::OutputEndpoint) =
    maybetaking(oe) ⨟ Map(x -> x === nothing ? Error(NoInput()) : x)

# ATM, no need to create a new object (so it's strange to call it "clone"?)
Julio.clone(h::ChannelHandle) = h
Julio.clone(ep::Endpoint) = ep.handle

function Base.open(handle::ChannelHandle)
    counter = selfcounter(handle)
    @trace label = :inc_start count = counter.value[] issend = handle isa InputEndpoint
    add!(counter, 1)
    @trace label = :inc_done count = counter.value[] issend = handle isa InputEndpoint
    if handle isa InputHandle
        return InputEndpoint(handle, Threads.Atomic{Bool}(false))
    else
        return OutputEndpoint(handle, Threads.Atomic{Bool}(false))
    end
end

Julio.open(ep::ChannelHandle) = open(ep)

function Base.close(ep::Endpoint)
    if Threads.atomic_cas!(ep.closed, false, true)
        return
    end
    counter = selfcounter(ep)
    @trace label = :dec_start count = counter.value[] issend = ep isa InputEndpoint
    add!(counter, -1)
    @trace label = :dec_done count = counter.value[] issend = ep isa InputEndpoint
    return
end

event(::typeof(put!), ie::InputEndpoint, x) = Return(convert(eltype(ie), x)) ⨟ putting(ie)
event(::typeof(push!), ie::InputEndpoint) = event(put!, ie, x)

function Base.put!(ie::InputEndpoint, x)
    @trace label = :put_start x
    apply(put!, ie, x)
    @trace label = :put_done
    return
end

event(::typeof(Julio.maybetake!), oe::OutputEndpoint) = maybetaking(oe)
Julio.maybetake!(oe::OutputEndpoint) = apply(Julio.maybetake!, oe)

event(::typeof(take!), oe::OutputEndpoint) = taking(oe)

function Base.take!(oe::OutputEndpoint)
    @trace label = :take_start
    ans = apply(take!, oe)
    @trace label = :take_done x = ans
    return ans
end

function Base.push!(ie::InputEndpoint, x)
    put!(ie, x)
    return ie
end

Base.IteratorSize(::Type{<:OutputEndpoint}) = Base.SizeUnknown()

function Base.iterate(oe::OutputEndpoint, ::Nothing = nothing)
    @trace label = :iterate_start
    x = cancellable_react!(taking(oe))
    @trace label = :iterate_done ans = x
    if x === Error(NoInput())
        return nothing
    else
        return (something(x), nothing)
    end
end

function (::Julio._OpenChannel{factory})(args...; kwargs...) where {factory}
    ih, oh = factory(args...; kwargs...)
    return open(ih), open(oh)
end

function (::Julio._ChannelContext{factory})(f::F, args...; kwargs...) where {F,factory}
    ih, oh = factory(args...; kwargs...)
    open(ih) do ie
        open(oh) do oe
            f(ie, oe)
        end
    end
end

function on_channel_handle_method_error(io::IO, exc::MethodError, argtypes, _kwargs)
    putfns = (put!, Julio.tryput!)
    takefns = (take!, Julio.maybetake!)
    length(argtypes) > 0 || return
    handle = argtypes[1]::Type
    if (
        (handle <: InputHandle && exc.f in putfns) ||
        (handle <: OutputHandle && exc.f in takefns)
    )
        println(io)
        printstyled(io, string(exc.f); color = :cyan)
        print(io, " requires an ")
        printstyled(io, "endpoint"; color = :cyan)
        print(io, " not a ")
        printstyled(io, "handle"; color = :cyan)
        print(io, ". Use ")
        printstyled(io, "open(handle)"; color = :cyan, bold = true)
        print(io, " to obtain an input endpoint.")
    elseif (
        (handle <: Union{OutputEndpoint,OutputHandle} && exc.f in putfns) ||
        (handle <: Union{InputEndpoint,InputHandle} && exc.f in takefns)
    )
        obj = handle <: ChannelHandle ? "handle" : "endpoint"
        required = exc.f in putfns ? "input" : "output"
        given = required == "input" ? "output" : "input"
        println(io)
        printstyled(io, string(exc.f); color = :cyan)
        print(io, " requires an ")
        printstyled(io, "$required endpoint"; color = :cyan, bold = true)
        print(io, " not an ")
        printstyled(io, "$given $obj"; color = :cyan)
        print(io, ". ")
        print(
            io,
            """
            Use the endpoint from the other handle. Example:

                input_handle, output_handle = Julio.channel()
                open($(required)_handle) do $(required)_endpoint
                    $(exc.f)($(required)_endpoint$(exc.f in putfns ? ", item" : ""))
                end

            """,
        )
        if handle <: ChannelHandle
            print(io, "Also note that an ")
            printstyled(io, "endpoint"; color = :cyan)
            print(io, " is required for $(exc.f) and not an $given ")
            printstyled(io, "handle"; color = :cyan)
            print(io, "; i.e., the $required handle must be opened to obtain")
            print(io, " an $required endpoint as illustrated above.")
        end
        println(io)
    end
end
