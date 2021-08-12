baremodule Julio

import DefineSingletons

# I/O
function open end
function openall end

# Task
function withtaskgroup end
function spawn! end

# Cancellation
function cancelscope end
function cancel! end
function oncancel end
function shield end
function withtimeout end
function timeout end
function sleep end

# Queue-like data structures
function channel end
function stack end
function queue end
function clone end

struct _OpenChannel{factory} end

# TODO: don't put factories in the type parameter (improve DefineSingletons)
DefineSingletons.@def_singleton openchannel = _OpenChannel{channel}()
DefineSingletons.@def_singleton openstack = _OpenChannel{stack}()
DefineSingletons.@def_singleton openqueue = _OpenChannel{queue}()

struct _ChannelContext{factory} end

# TODO: don't put factories in the type parameter (improve DefineSingletons)
DefineSingletons.@def_singleton withchannel = _ChannelContext{channel}()
DefineSingletons.@def_singleton withstack = _ChannelContext{stack}()
DefineSingletons.@def_singleton withqueue = _ChannelContext{queue}()

function maybetake! end
function tryput! end
function maybefetch end

# Low-level APIs
function select end
function sync end
function yield end
function checkpoint end

# DefineSingletons.@def_singleton var"try" isa Function
DefineSingletons.@def_singleton Events

module Internal

using ..Julio: Julio
using ArgCheck: @argcheck
using ContextVariablesX
using Reagents
using Reagents:
    Block,
    CAS,
    Computed,
    Identity,
    Map,
    PostCommit,
    Read,
    Reagents,
    Retry,
    Return,
    Update,
    WithNack

struct PleaseUseBaseDotReturns end
const Returns = PleaseUseBaseDotReturns()

include("utils.jl")
include("tracing.jl")

include("core.jl")
include("promises.jl")
include("base.jl")
include("watch.jl")
include("stacks.jl")
include("queues.jl")
include("blocking.jl")
include("channels.jl")
include("taskgroups.jl")
include("locks.jl")

include("resizable.jl")
include("io.jl")

include("api.jl")
include("docs.jl")

function __init__()
    try
        Base.Experimental.register_error_hint(on_channel_handle_method_error, MethodError)
    catch err
        @warn "Failed to register an error hint" exception = (err, catch_backtrace())
    end
end

end  # module Internal

const Promise = Internal.Promise
const Lock = Internal.Lock

Internal.define_docstrings()

end  # baremodule Julio
