module JulioTests

include("utils.jl")
include("test_stack.jl")
include("test_taskgroups.jl")
include("test_channels.jl")
include("test_promise.jl")
include("test_io.jl")
include("test_locks.jl")
include("test_select.jl")
include("test_cancellation.jl")
include("test_introduction.jl")
include("test_structured_concurrency.jl")
include("test_search3.jl")
include("test_happy_eyeballs.jl")
include("test_custom_select.jl")
include("test_contextmanagers.jl")
include("test_dying_philosopher.jl")
include("test_doctest.jl")

end  # module JulioTests
