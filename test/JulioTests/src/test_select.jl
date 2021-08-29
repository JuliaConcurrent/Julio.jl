module TestSelect

using Julio
using Test

include("../../../examples/select.jl")

function test_select_take()
    output = nothing
    selected = nothing
    ie1, _ = Julio.channel(Int)
    ie2, oe2 = Julio.stack(Int)
    begin
        begin
            put!(ie2, 222)
            Julio.select(
                (put!, ie1, 111) => _ -> begin
                    selected = :put!
                end,
                (take!, oe2) => x -> begin
                    output = x
                    selected = :take!
                end,
            )
        end
    end
    @test selected === :take!
    @test output == 222
end

function test_select_cmd()
    Julio.open(`echo "hello"`) do io
        _, o1 = Julio.channel()
        begin
            selected = Julio.select(
                Events.readline(io; keep = true),  # should win
                (take!, o1),
            )
            @test selected == "hello\n"
        end
    end
end

end  # module
