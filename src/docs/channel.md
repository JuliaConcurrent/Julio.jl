    Julio.channel(T::Type = Any) -> (input_handle, output_handle)

`Julio.channel` creates a unbuffered channel and return a pair of `input_handle`
and `output_handle`.  The `input_handle` and `output_handle` can be `open`ed to
obtain `input_endpoint` and `output_endpoint` for sending and receiving items
through the channel respectively.

Following methods are supported by the channel:

```JULIA
open(input_handle) -> input_endpoint
open(output_handle) -> output_endpoint
put!(input_endpoint, item::T)
Julio.tryput!(input_endpoint, item::T) -> success::Bool
take!(output_endpoint) -> item::T
Julio.maybetake!(output_endpoint) -> Some(item) or nothing
close(input_endpoint)
close(output_endpoint)
```
