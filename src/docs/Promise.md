    Julio.Promise{T}()
    Julio.Promise()

Create a promise.

A value of type `T` (or `Any` if unspecified) can be set once by `put!`.
Calling `fetch` blocks until `put!` is called.

The indexing notation `p[]` can be used as a synonym for `put!` and `fetch`.

# Example

```julia
julia> using Julio

julia> p = Julio.Promise();

julia> p[] = 111;

julia> p[]
111

julia> Julio.withtaskgroup() do tg
           p = Julio.Promise{Int}()
           Julio.spawn!(tg) do
               p[] = 222
           end
           p[]
       end
222
```
