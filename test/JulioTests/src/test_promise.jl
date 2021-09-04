module TestPromise

using Julio
using Test

function test_int()
    p = Julio.Promise{Int}()
    p[] = 111
    @test p[] == 111
end

function test_any()
    p = Julio.Promise()
    p[] = 111
    @test p[] == 111
end

function test_someany()
    p = Julio.Promise{Some{Any}}()
    p[] = Some{Any}(111)
    @test p[] === Some{Any}(111)
end

function test_union_someany_missing()
    p = Julio.Promise{Union{Some{Any},Missing}}()
    p[] = Some{Any}(111)
    @test p[] === Some{Any}(111)

    p = Julio.Promise{Union{Some{Any},Missing}}()
    p[] = missing
    @test p[] === missing
end

end  # module
