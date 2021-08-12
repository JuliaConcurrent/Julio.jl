```@eval
Main._BANNER_
```

# Julio.jl

Julio is an implementation of [structured
concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) for Julia.
It is inspired by [Trio](https://github.com/python-trio/trio) and
[Curio](https://github.com/dabeaz/curio).

It is built on top of [Reagents.jl](https://github.com/tkf/Reagents.jl), a
composable framework for nonblocking and synchronization algorithms influenced
by [Concurrent ML](https://en.wikipedia.org/wiki/Concurrent_ML).
