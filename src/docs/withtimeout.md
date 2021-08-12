    Julio.withtimeout(f, seconds) -> Some(ans) or nothing

Run `f()` with timeout `seconds`.  If it finishes with output value `ans` before
the timeout, return `Some(ans)`.  Return `nothing` otherwise.

Note that blocking operations must use Julio API for automatic cancellation;
`Julio.sleep` instead of `sleep`, `read(Julio.open(io))` instead of `read(io)`,
and so on.  Use `Julio.` Non-Julio API can be cancelled using
[`Julio.oncancel`](@ref).

## Example

```julia
julia> using Julio

julia> Julio.withtimeout(0.1) do
           Julio.sleep(60)
       end === nothing  # too slow
true

julia> Julio.withtimeout(60) do
           Julio.sleep(0.1)
       end === Some(nothing)  # success
true
```
