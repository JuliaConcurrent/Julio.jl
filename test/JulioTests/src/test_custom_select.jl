module TestCustomSelect

include("../../../examples/custom_select.jl")

function test_broadcastchannel_repeat()
    @testset for trial in 1:8
        ans = test_broadcastchannel()
        @debug "`test_broadcastchannel_repeat`" ans
    end
end

end  # module
