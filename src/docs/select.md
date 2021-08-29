    Julio.select(ev₁, ev₂, ..., evₙ) -> ansᵢ

Select and execute one and only one event `evᵢ` (`1 ≤ i ≤ n`) and return its
result `ansᵢ`.

An even has the following format

```JULIA
(f, args...)
(f, args...) => g
Julio.Events.f(args...; kwargs...)
Julio.Events.f(args...; kwargs...) => g
```

where `f` is a function such as `take!` and `put!`, `args` are their arguments,
`kwargs` are the named arguments, and `g` is a unary function that receives the
output of `(f, args...)` or `Julio.Events.f(args...; kwargs...)`.  If `g` is not
specified, `identity` is used instead.

## Examples

```JULIA
using Julio: Events

Julio.select(
    (Julio.tryput!, send_endpoint, item),
    (take!, receive_endpoint) => item -> begin
        println("Got: ", item)
    end,
    Event.put!(another_send_endpoint, item),
    Event.readline(io; keep = true) => line -> begin
        println("Read line: ", line)
    end,
)
```
