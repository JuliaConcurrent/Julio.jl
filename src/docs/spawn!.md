    Julio.spawn!(f, tg, args...) -> task

Run a function `f` with arguments `args` inside a task managed by the task group
`tg`.

Input and output handles of channel passed via `args` are automatically opened
before scheduling the task and closed before the task ends.

See [`Julio.withtaskgroup`](@ref).

## Example

```julia
julia> using Julio

julia> ih, oh = Julio.queue();

julia> Julio.withtaskgroup() do tg
           Julio.spawn!(tg, ih, 111) do ie, x  # opens `ih`
               put!(ie, x)
           end
           Julio.spawn!(tg, oh) do oe  # opens `oh`
               @show take!(oe)
           end
       end;
take!(oe) = 111
```
