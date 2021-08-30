# # Example: Dying philosopher

using Julio
using ContextManagers: @with, onfail

# Following function demonstrate the [Dining philosophers problem -
# Wikipedia](https://en.wikipedia.org/wiki/Dining_philosophers_problem) and a
# "quick-and-dirty" way to recover from the deadlock by killing a philosopher
# after a timeout.
#
# This example is based on
# [David Beazley - Die Threads - YouTube](https://www.youtube.com/watch?v=xOyJiN3yGfU)
# which demonstrated this with a threading library for Python called
# [Thredo](https://github.com/dabeaz/thredo).

function dying_philosopher(nphils = 5)
    sticks = [Julio.Lock() for _ in 1:nphils]
    Julio.withtaskgroup() do tg
        phils = [Julio.cancelscope() for _ in 1:nphils]
        for (n, scope) in pairs(phils)
            Julio.spawn!(tg) do
                open(scope) do
                    @with(sticks[n]) do
                        sleep(rand())
                        @with(
                            onfail() do
                                println("But what is death? $n")
                            end,
                            sticks[mod1(n + 1, nphils)]
                        ) do
                            println("eating $n")
                        end
                    end
                end
            end
        end
        Julio.spawn!(tg) do
            sleep(10)
            n = rand(1:nphils)
            println("Killing philosopher $n")
            Julio.cancel!(phils[n])
        end
    end
end

# Running the above function prints something like
#
# ```julia
# julia> dying_philosopher();
# Killing philosopher 4
# But what is death? 4
# eating 3
# eating 2
# eating 1
# eating 5
# ```
#
# Of course, this is not a "correct" solution to the dining philosophers problem
# *per se*. However, it is easy to accidentally write a program producing
# deadlocks and discovering this in an interactive session. It is important that
# we can reliably recover from a deadlock with `Ctrl+C` without breaking the
# entire Julia runtime so that we can debug the program. It helps writing and
# fixing concurrent programs.
