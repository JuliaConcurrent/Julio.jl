Julio.open(f, a, args...; kwargs...) = withopen(f, a, args...; kwargs...)

function withopen(f, a, args...; kwargs...)
    resource = Julio.open(a, args...; kwargs...)
    try
        f(resource)
    finally
        close(resource)
    end
end

Julio.openall(f, resource) = Julio.open(f, resource)
function Julio.openall(f, resource1, resource2, resources...)
    arg1 = Julio.open(resource1)
    try
        Julio.openall(resource2, resources...) do args...
            f(arg1, args...)
        end
    finally
        close(arg1)
    end
end

# Implement `Julio.Events.f(args...; kwargs...)`
function Base.getproperty(::typeof(Julio.Events), name::Symbol)
    f = getfield(Base, name)
    event_factory(args...; kwargs...) = event(f, args...; kwargs...)
    return event_factory
end
