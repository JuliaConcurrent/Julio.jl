    Julio.Events.f(args...; kwargs...)

`Julio.Events.f(args...; kwargs...)` creates an *event* (i.e., an object
describing how to execute `f(args...; kwargs...)`) that can be passed to
[`Julio.select`](@ref).

## Example

Unlike `(f, args...)` syntax that is also accepted by `Julio.select`,
`Events.f(args...)` may have some states. For example, `Events.sleep(seconds)`
sets the timeout at the time the event is created and not when it is passed to
`Julio.select`:

```julia
julia> using Julio: Julio, Events

julia> Julio.withtaskgroup() do tg
           Julio.spawn!(tg) do
               ev = Events.sleep(0.1)  # countdown starts now
               while true
                   Julio.select(
                       ev => Returns(true),  # eventually this event wins
                       Events.sleep(0) => Returns(false),
                   ) && break
               end
           end
       end;
```
