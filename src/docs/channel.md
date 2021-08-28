    Julio.channel(T::Type = Any) -> (send_endpoint, receive_endpoint)

`Julio.channel` creates a unbuffered channel and return a pair of
`send_endpoint` and `receive_endpoint`.

Following methods are supported by the channel:

```JULIA
put!(send_endpoint, item::T)
Julio.tryput!(send_endpoint, item::T) -> success::Bool
take!(receive_endpoint) -> item::T
Julio.maybetake!(receive_endpoint) -> Some(item) or nothing
close(send_endpoint)
close(receive_endpoint)
```
