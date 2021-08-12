    Julio.open(io::IO; close = false) -> wrapped_io::IO

Wrap an IO object into a new IO that is usable via Julio's synchronization API.

    Julio.open(x::AbstractCommand, args...)
    Julio.open(x::AbstractString, args...)

Synonym of `Julio.open(open(x, args...); close = true)`.

    Julio.open(f, x, args...)

A shorthand for

```JULIA
resource = Julio.open(x, args...)
try
    f(resource)
finally
    close(resource)
end
```
