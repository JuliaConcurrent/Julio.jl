    Julio.withtaskgroup(f) -> ans

Create a task group `tg` and pass it to the function `f` of the form `tg ->
ans`.

See [`Julio.spawn!`](@ref).

## Example

```julia
julia> using Julio

julia> Julio.withtaskgroup() do tg
           Julio.spawn!(tg) do
               println("hello")
           end
       end;
hello
```
