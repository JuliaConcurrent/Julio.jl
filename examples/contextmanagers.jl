using ContextManagers: @with, SharedResource
using Julio
using Test

function test_channel()
    Julio.withtaskgroup() do tg
        send_endpoint, receive_endpoint = Julio.channel()
        @with(shared_send = SharedResource(send_endpoint)) do
            for i in 1:5
                Julio.spawn!(tg, shared_send) do send_endpoint
                    put!(send_endpoint, i)
                end
            end
        end
        @with(receive_endpoint) do
            @test sort!(collect(receive_endpoint)) == 1:5
        end
    end
end
