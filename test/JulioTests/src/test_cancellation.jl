module TestCancellation

using Julio
using Test
using ..Utils: @test_error, ⊏

function test_onclose()
    ncalls = Ref(0)
    err = @test_error Julio.withtaskgroup() do tg
        Julio.oncancel() do
            ncalls[] += 1
        end
        error("_CANCELLING_")
    end
    @test "_CANCELLING_" ⊏ sprint(showerror, err)
    @test ncalls[] == 1
end

function test_shield()
    ie1, oe1 = Julio.openchannel()
    ie2, oe2 = Julio.openchannel()
    ie3, oe3 = Julio.openchannel()
    local task
    Julio.withtaskgroup() do tg
        task = Julio.spawn!(tg) do
            @test_error Julio.withtaskgroup() do tg
                Julio.spawn!(tg) do
                    Julio.shield() do
                        put!(ie2, :enter_shield)
                        put!(ie2, :leave_shield)
                    end
                end
                Julio.spawn!(tg) do
                    try
                        put!(ie3, :waiting)
                    finally
                        Julio.shield() do
                            put!(ie1, :thrown)
                        end
                    end
                end
                error("_CANCELLING_")
            end
        end
        @test take!(oe2) === :enter_shield
        @test take!(oe1) === :thrown
        @test take!(oe2) === :leave_shield
    end
    @test "_CANCELLING_" ⊏ sprint(showerror, fetch(task))
end

function spin()
    while true
        Julio.yield()
    end
end

function test_yield()
    Julio.withtaskgroup() do tg
        Julio.spawn!(spin, tg)
        Julio.spawn!(spin, tg)
        sleep(0.01)
        Julio.cancel!(tg)
    end
    @test true
end

function test_nested_cancel()
    timeout = Ref(false)
    Julio.withtaskgroup() do tg0
        Julio.withtaskgroup() do tg1
            Julio.spawn!(tg1) do
                Julio.sleep(10)
                timeout[] = true
            end
            Julio.cancel!(tg0)
        end
    end
    @test !timeout[]
end

end  # module
