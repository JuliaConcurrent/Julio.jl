# # Example: Happy Eyeballs

using Sockets
using Julio
using Test

# An implementation of Happy Eyeballs (RFC 8305)
# <https://datatracker.ietf.org/doc/html/rfc8305>
#
# (TODO: verify)

function happy_eyeballs(host, port; delay = 0.3)
    addrs = getalladdrinfo(host)
    winner = Julio.Promise()
    decided = nothing
    allsockets = TCPSocket[]
    Julio.withtaskgroup() do tg
        issuccess = false
        try
            failureevents = []
            for ip in addrs
                failed = Julio.Promise{Nothing}()
                push!(failureevents, failed)
                socket = TCPSocket()
                push!(allsockets, socket)
                Julio.spawn!(tg) do
                    inject_latencies(ip == addrs[end])                      #src
                    try
                        connect(socket, ip, port)
                    catch err
                        if err isa Base.IOError
                            failed[] = nothing
                            return
                        elseif Julio.iscancelled()
                            return
                        end
                        rethrow()
                    end
                    Julio.tryput!(winner, socket)
                end
                Julio.select(
                    (fetch, winner) => socket -> begin
                        decided = socket
                        true
                    end,
                    (fetch, failed) => _ -> false,
                    (sleep, delay) => _ -> false,
                ) && break
            end
            if decided === nothing
                for failed in failureevents
                    Julio.select(
                        (fetch, winner) => socket -> begin
                            decided = socket
                            true
                        end,
                        (fetch, failed) => _ -> false,
                    ) && break
                end
            end
            issuccess = true
        finally
            for socket in allsockets
                if !issuccess || socket !== decided
                    close(socket)
                end
            end
        end
    end
    for socket in allsockets                                                #src
        if socket !== decided                                               #src
            @test !isopen(socket)                                           #src
        end                                                                 #src
    end                                                                     #src
    return decided
end

# * [Nathaniel J. Smith - Trio: Async concurrency for mere mortals - PyCon 2018 - YouTube](https://www.youtube.com/watch?v=oLkfnc_UMcE)
# * [Two Approaches to Structured Concurrency - 250bpm](https://250bpm.com/blog:139/)

function test_happy_eyeballs()
    socket = happy_eyeballs("httpbin.org", 80)
    try
        @test socket isa TCPSocket
        @test isopen(socket)
    finally
        close(socket)
    end
end

# For reproducing "TCPSocket is not in initialization state" error:         #src
@isdefined(inject_latencies) || begin                                       #src
    inject_latencies(_) = nothing                                           #src
end                                                                         #src
