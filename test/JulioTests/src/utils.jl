module Utils

using Test

function random_sleep(spawn::Bool = true)
    if rand() < 0.1
        # no sleep
    elseif spawn && rand(Bool)
        nspins = rand(0:10000)
        for _ in 1:nspins
            GC.safepoint()
            ccall(:jl_cpu_pause, Cvoid, ())
        end
    else
        sleep(rand() / 1_000_000)
    end
end

function trywait(task::Task, seconds::Real = 0.1)
    istaskdone(task) && wait(task)
    delta = 0.01
    for _ in 0.0:delta:seconds
        sleep(delta)
        if istaskdone(task)
            wait(task)
            break
        end
    end
    return istaskdone(task)
end

macro test_error(expr)
    @gensym err tmp
    quote
        local $err = nothing
        $Test.@test try
            $expr
            false
        catch $tmp
            $err = $tmp
            true
        end
        $err
    end |> esc
end

const ⊏ = occursin

end  # module
