# Julio: Structured Concurrency for Julia

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tkf.github.io/Julio.jl/dev/)

Julio is an implementation of [structured
concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) for Julia.
It is inspired by [Trio](https://github.com/python-trio/trio) and
[Curio](https://github.com/dabeaz/curio).

It is built on top of [Reagents.jl](https://github.com/tkf/Reagents.jl), a
composable framework for nonblocking and synchronization algorithms influenced
by [Concurrent ML](https://en.wikipedia.org/wiki/Concurrent_ML).

See more in the [documentation](https://tkf.github.io/Julio.jl/dev/).

## Features

* Structured concurrency
  * No more stray tasks
    ([Black box rule](https://tkf.github.io/Julio.jl/dev/explanation/structured_concurrency/#black-box))
  * [Concurrent error handling](https://tkf.github.io/Julio.jl/dev/explanation/structured_concurrency/#Error-handling)
  * [Unified cancellation interface](https://tkf.github.io/Julio.jl/dev/tutorials/introduction/#man-cancel-scope)
* [`Julio.select`](https://tkf.github.io/Julio.jl/dev/tutorials/select/) for
  selective synchronization
  * [Select on arbitrary *event* not just channels](https://tkf.github.io/Julio.jl/dev/tutorials/select/#Selecting-an-arbitrary-event)
  * [Extensible event selection](https://tkf.github.io/Julio.jl/dev/tutorials/custom_select/)
