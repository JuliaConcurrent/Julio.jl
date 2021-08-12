module TestDoctest

using Documenter
using Test
using Julio

function test()
    doctest(Julio; manual = true)
end

end  # module
