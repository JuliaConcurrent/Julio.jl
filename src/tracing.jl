taskid(task::Task = current_task()) = objectid(task)

const Recalls = try
    Base.require(Base.PkgId(Base.UUID(0x30af7cf3eb4344c7afa733725b72a81e), "Recalls"))
catch
    nothing
end

istracing() = false

macro trace(args...)
    Recalls === nothing && return nothing
    note = :($Recalls.@note(taskid = $(taskid)(), $(args...),))
    @assert note.head === :macrocall
    @assert note.args[2] isa LineNumberNode
    note.args[2] = __source__
    quote
        if $istracing()
            $note
        end
        nothing
    end |> esc
end
# TODO: Use Preferences.jl to controll if Recalls.jl should be loaded? Since
# `args` may affect what variables are captured in closures, the existence of
# Recalls.jl changes the program slightly.

function enable_tracing()
    if Recalls === nothing
        error(
            "Tracing requires Recalls.jl to be installed in the same environment.",
            " See: https://github.com/tkf/Recalls.jl",
        )
    end
    prev = istracing()
    @eval istracing() = true
    return prev
end

function disable_tracing()
    prev = istracing()
    @eval istracing() = false
    return prev
end
