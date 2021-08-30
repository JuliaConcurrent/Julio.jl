struct Cancelled <: Exception end

cancellation_token() = Promise{Cancelled}()

const CancellationTokenType = typeof(cancellation_token())

const DissolveHandle = let
    send, _ = Reagents.channel()
    handle = Reagents.dissolve(send)
    typeof(handle)
end

struct CancelScope
    token::CancellationTokenType
    dissolvehandle::Union{DissolveHandle,Nothing}
end

# TODO: store `CancelScope`?
@contextvar CANCELLATION_TOKEN::Union{CancellationTokenType,Nothing} = nothing

function Julio.cancel!(token::CancellationTokenType)
    tryputting(token)(Cancelled())
end

function withopen(f, scope::CancelScope)
    try
        with_context(f, CANCELLATION_TOKEN => scope.token)
    catch err
        if iscancelled(err) && is_token_cancelled(scope.token) && !Julio.iscancelled()
            return
        end
        rethrow()
    end
end

# Unfortunately, other `Base.open` methods uses `Function`...
Base.open(f::Function, scope::CancelScope) = withopen(f, scope)

# const CancellationTokenRefType = typeof(Reagents.Ref{Promise{Cancelled}}())

# @contextvar CANCELLATION_TOKEN::CancellationTokenRefType = CancellationTokenRefType()

function waiting_cancel()
    token = CANCELLATION_TOKEN[]
    if token === nothing
        return Return(Block())
    else
        if istracing()
            cancelled = PostCommit(_ -> @trace(label = :cancelled))
            # cancelled = PostCommit(_ -> (yield(); @trace(label = :cancelled)))
        else
            cancelled = Identity()
        end
        return fetching(token) ⨟ cancelled
    end
end

function cancellable_react!(reagent::Reagents.Reagent, x = nothing)
    ans = (waiting_cancel() | reagent)(x)
    if ans isa Cancelled
        throw(ans)
    end
    return ans
end

@inline function handle_result(@nospecialize(ans))
    if ans isa EventResult
        return ans.f()
    elseif ans isa Error
        throw(ans.value)
    elseif ans === nothing
        return nothing
    else
        return something(ans)
    end
end

Julio.sync(reagent::Reagents.Reagent, x = nothing) =
    handle_result(cancellable_react!(reagent, x))

# TODO: formalize output format better (should we use a sum type always?)
# TODO: unify this with `handle_result`
asresult(f) =
    Map() do ans
        if ans isa Error
            return ans
        else
            x = something(ans, Some(nothing))
            return EventResult(() -> f(x))
        end
    end

lowerevent(reagent::Reagents.Reagent) = reagent
lowerevent((reagent, f)::Pair{<:Reagents.Reagent}) = reagent ⨟ asresult(f)
lowerevent((fargs, f)::Pair{<:Tuple}) = event(fargs...) ⨟ asresult(f)
lowerevent(fargs::Tuple) = event(fargs...)

function Julio.select(event1, events...)
    reagent = mapfoldl(lowerevent, |, (event1, events...))
    return handle_result(cancellable_react!(reagent))
end

#=
struct TryFailed end

function Julio.try(f, args...)
    y = Julio.sync(event(f, args...) | Return(TryFailed()))
    return !(y isa TryFailed)
end
=#

apply(f, args...) = Julio.sync(lowerevent((f, args...)))

function Julio.withtimeout(f::F, seconds::Real) where {F}
    token = cancellation_token()
    with_context(CANCELLATION_TOKEN => token) do
        timer = Timer(seconds) do _
            Julio.cancel!(token)
        end
        try
            return Some(f())
        catch err
            err isa Cancelled && return nothing
            rethrow()
        finally
            close(timer)
        end
    end
end

event(::typeof(Julio.sleep), seconds::Real) = event(sleep, seconds)
function event(::typeof(sleep), seconds::Real)
    promise = Julio.Promise{Nothing}()
    Timer(seconds) do _
        put_nocancel!(promise, nothing)
    end
    return fetching(promise)
end

Julio.sleep(seconds) = apply(sleep, seconds)

Julio.shield(f) = with_context(f, CANCELLATION_TOKEN => nothing)

function Julio.oncancel(f, args...; kwargs...)
    token = @something(CANCELLATION_TOKEN[], return nothing)
    reagent = fetching(token) ⨟ PostCommit() do _
        f(args...; kwargs...)
    end
    return Reagents.dissolve(reagent; once = true)
end

Julio.cancel!(handle::DissolveHandle) = Reagents.clear!(handle)
