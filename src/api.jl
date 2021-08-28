Julio.open(f, a, args...; kwargs...) = withopen(f, a, args...; kwargs...)

function withopen(f, a, args...; kwargs...)
    resource = Julio.open(a, args...; kwargs...)
    try
        f(resource)
    finally
        close(resource)
    end
end

# Implement `Julio.Events.f(args...; kwargs...)`
function Base.getproperty(::typeof(Julio.Events), name::Symbol)
    f = getfield(Base, name)
    event_factory(args...; kwargs...) = event(f, args...; kwargs...)
    return event_factory
end
