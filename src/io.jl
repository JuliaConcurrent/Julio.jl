const READSTATE_INIT = 0
const READSTATE_STARTED = 1
const READSTATE_CANCELLED = 2

startreply!(state::Threads.Atomic{Int}) =
    Threads.atomic_cas!(state, READSTATE_INIT, READSTATE_STARTED) == READSTATE_INIT

cancelrequest!(state::Threads.Atomic{Int}) =
    Threads.atomic_cas!(state, READSTATE_INIT, READSTATE_CANCELLED) == READSTATE_INIT

struct ReadBytesReq
    out::Vector{UInt8}
    nbytes::Int
    state::Threads.Atomic{Int}
    waitwrite::typeof(Promise{Nothing}())
end

struct ReadUntilVectorReq
    target::Vector{UInt8}
    keep::Bool
    out::Vector{UInt8}
    state::Threads.Atomic{Int}
    waitwrite::typeof(Promise{Nothing}())
end

struct UnsafeWriteReq
    out::Vector{UInt8}
    nbytes::UInt
end

struct IOManager{Raw<:IO}
    raw::Raw
    buffer::Vector{UInt8}
    request_send::typeof(Reagents.channel(Any, Nothing)[1])
    request_receive::typeof(Reagents.channel(Any, Nothing)[2])
    shutdown::typeof(Promise{Nothing}())
    sent::typeof(Ref(0))
end

struct IOWrapper{Raw<:IO} <: IO
    manager::IOManager{Raw}
    task::Task
    close_raw::Bool
end

function Julio.open(raw::IO; close = false)
    request_send, request_receive = Reagents.channel(Any, Nothing)
    shutdown = Promise{Nothing}()
    manager = IOManager(
        raw,
        empty!(Vector{UInt8}(undef, 1024)),
        request_send,
        request_receive,
        shutdown,
        Ref(0),
    )
    task = Threads.@spawn manage!(manager)
    return IOWrapper(manager, task, close)
end

function Base.close(io::IOWrapper)
    Reagents.trysync!(tryputting(io.manager.shutdown), nothing)
    if io.close_raw
        close(io.manager.raw)
        wait(io.task)
    elseif istaskdone(io.task)
        wait(io.task)  # let it throw
    else
        errormonitor(io.task)  # TODO: Find a less unstructured handling.
    end
end

function manage!(manager::IOManager)
    (; request_receive, shutdown) = manager
    shutdown_receive = fetching(shutdown)
    # shutdown_receive = shutdown_receive ⨟ PostCommit(_ -> @info "shutting down")
    while true
        try_receive = request_receive | shutdown_receive
        (; request, reply, abort) = @something(try_receive(), break)
        ans = try
            Some(exec!(request, manager))
        catch err
            # @error "`exec!`" exception = (err, catch_backtrace())
            Error(err)
        end
        try_reply = (
            (Return(ans) ⨟ reply ⨟ Return(true)) |
            (abort ⨟ Return(false)) |
            shutdown_receive
        )
        @trace(label = :iomanager_start_try_reply)
        if @something(try_reply(), break)
            commit!(manager)
        else
            @trace(label = :iomanager_aborted)
        end
    end
    @trace(label = :iomanager_done)
    return
end

function commit!(manager::IOManager)
    (; buffer, sent) = manager
    # TODO: lazily move elements
    deleteat!(buffer, 1:sent[])
    @trace(label = :iomanager_commit, sent = sent[], buffer_length = length(buffer))
    sent[] = 0
end

function send!(manager::IOManager, request)
    (; request_send) = manager
    return Reagents.WithNack() do abort
        reply, receive = Reagents.channel(Any, Nothing)
        request_send((; request, reply, abort))
        return receive
    end
end

function readbytes_append!(io, buffer, nbytes)
    readbytes!(io, resizabletail(buffer), nbytes - length(buffer))
    return buffer
end

event(
    ::typeof(readbytes!),
    io::IOWrapper,
    out::Vector{UInt8},
    nbytes::Integer,
    state::Threads.Atomic{Int},
    waitwrite::Promise{Nothing},
) = send!(io.manager, ReadBytesReq(out, nbytes, state, waitwrite))

function exec!(request::ReadBytesReq, manager::IOManager)
    (; raw, buffer, sent) = manager
    (; out, nbytes, state, waitwrite) = request
    if nbytes <= length(buffer)
        startreply!(state) || return 0
        try
            sent[] = nbytes
            resize!(out, nbytes)
            copyto!(out, @view buffer[1:nbytes])
            @trace(label = :readbytes_use_buffer, sent = sent[])
        finally
            waitwrite[] = nothing
        end
    else
        # TODO: chunk large `nbytes` and check for cancellation
        readbytes_append!(raw, buffer, nbytes)
        startreply!(state) || return 0
        try
            sent[] = length(buffer)
            resize!(out, length(buffer))
            copyto!(out, buffer)
            @trace(label = :readbytes_read_raw, sent = sent[])
        finally
            waitwrite[] = nothing
        end
    end
    return sent[]
end

event(
    ::typeof(Base.readuntil_vector!),
    io::IOWrapper,
    target::Vector{UInt8},
    keep::Bool,
    out::Vector{UInt8},
    state::Threads.Atomic{Int},
    waitwrite::Promise{Nothing},
) = send!(io.manager, ReadUntilVectorReq(target, keep, out, state, waitwrite))

function exec!(request::ReadUntilVectorReq, manager::IOManager)
    (; raw, buffer, sent) = manager
    (; target, keep, out, state, waitwrite) = request
    iobuf = IOBuffer(buffer)
    if has_subseq(buffer, target)
        startreply!(state) || return
        try
            Base.readuntil_vector!(iobuf, target, keep, out)
        finally
            waitwrite[] = nothing
        end
    else
        Base.readuntil_vector!(raw, target, true, resizabletail(buffer))
        if keep
            result = @view buffer[begin:end]
        else
            result = @view buffer[begin:end-length(target)]
        end
        startreply!(state) || return
        try
            resize!(out, length(result))
            copyto!(out, result)
        finally
            waitwrite[] = nothing
        end
    end
    sent[] = length(buffer)
    return
end

function event(::typeof(unsafe_write), io::IOWrapper, ptr::Ptr{UInt8}, nbytes::UInt)
    # For cancel-safety, we need to copy the input now:
    out = Vector{UInt8}(undef, nbytes)
    copyto!(out, unsafe_wrap(Array, ptr, nbytes))
    send!(io.manager, UnsafeWriteReq(out, nbytes))
end

function exec!(request::UnsafeWriteReq, manager::IOManager)
    (; raw) = manager
    (; out, nbytes) = request
    GC.@preserve out begin
        ans = unsafe_write(raw, pointer(out), nbytes)
    end
    return ans
end

function event(::typeof(read), io::IOWrapper, nbytes::Integer = typemax(Int))
    state = Threads.Atomic{Int}()
    waitwrite = Promise{Nothing}()
    out = UInt8[]
    return event(readbytes!, io, out, nbytes, state, waitwrite) ⨟ Return(Some(out))
end

function event(::typeof(readline), io::IOWrapper; keep::Bool = false)
    if Sys.iswindows()
        target = collect(transcode(UInt8, "\r\n"))
    else
        target = collect(transcode(UInt8, "\n"))
    end
    return Computed() do _
        state = Threads.Atomic{Int}()
        waitwrite = Promise{Nothing}()
        out = UInt8[]
        return event(Base.readuntil_vector!, io, target, keep, out, state, waitwrite) ⨟
               Map() do _
            Some(String(out))
        end
    end
end

# ## Blocking interface

function Base.readbytes!(io::IOWrapper, out::Vector{UInt8}, nbytes::Integer = typemax(Int))
    state = Threads.Atomic{Int}()
    waitwrite = Promise{Nothing}()
    try
        return Julio.sync(event(readbytes!, io, out, nbytes, state, waitwrite))
    finally
        cancelrequest!(state) || fetch(waitwrite)
        # TODO: automate this (`out` ownership/locking handling)?
    end
end

function Base.readuntil_vector!(
    io::IOWrapper,
    target::Vector{UInt8},
    keep::Bool,
    out::Vector{UInt8},
)
    state = Threads.Atomic{Int}()
    waitwrite = Promise{Nothing}()
    try
        return Julio.sync(
            event(Base.readuntil_vector!, io, target, keep, out, state, waitwrite),
        )
    finally
        cancelrequest!(state) || fetch(waitwrite)
    end
end

function Base.readuntil(io::IOWrapper, delim::UInt8; keep::Bool = false)
    out = UInt8[]
    Base.readuntil_vector!(io, [delim], keep, out)
    return out
end

Base.unsafe_write(io::IOWrapper, ptr::Ptr{UInt8}, nbytes::UInt) =
    Julio.sync(event(unsafe_write, io, ptr, nbytes))

Julio.open(path::AbstractString; kwargs...) =
    Julio.open(open(path; kwargs...); close = true)

Julio.open(cmd::Base.AbstractCmd, args...; kwargs...) =
    Julio.open(open(cmd, args...; kwargs...); close = true)

function withopen(f, cmd::Base.AbstractCmd, args...; kwargs...)
    open(cmd, args...; kwargs...) do io
        withopen(f, io)
    end
end
