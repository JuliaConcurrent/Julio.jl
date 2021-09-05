module TestStack

using Julio
using Julio.Internal: maybepop_nowait!
using Test

function test_pushpop()
    s = Julio.Internal.TreiberStack{Int}()
    push!(s, 111)
    push!(s, 222)
    @test something(maybepop_nowait!(s)) == 222
    @test something(maybepop_nowait!(s)) == 111
    @test maybepop_nowait!(s) === nothing
end

function test_iter()
    s = Julio.Internal.TreiberStack{Int}()
    push!(s, 111)
    push!(s, 222)
    @test collect(s) == [222, 111]
end

end  # module
