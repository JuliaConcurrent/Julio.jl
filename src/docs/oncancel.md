    Julio.oncancel(f, args...) -> handle

Register a cancellation callback `f` and its arguments `args` to the current
cancellation scope.  This callback is triggered via `Julio.cancel!(tg)` or
`Julio.cancel!(scope)`.

The registered callback can be removed by `Julio.cancel!(handle)`.

See also: [`Julio.cancel!`](@ref).

## Example

```julia
julia> using Julio

julia> Julio.withtaskgroup() do tg
           Julio.spawn!(tg) do
               ch = Channel()  # non Julio API
               Julio.oncancel(close, ch)  # close the channel on cancellation
               try
                   take!(ch)  # blocks forever
               catch
                   isopen(ch) && rethrow()  # ignore the exception due to `close`
               end
           end
           Julio.cancel!(tg)
       end;
```
