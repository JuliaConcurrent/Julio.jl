# # Google Search 3.0

using Julio
using Julio: Events

# This is an example taken from Rob Pike's 2012 talk *Go Concurrency Patterns*.

# Avoid timeout (search engine replicas)
# <https://talks.golang.org/2012/concurrency.slide#48>

# `replicas` is a tuple of callables with the signature `query -> promise`;
# e.g., `replicas = webs = (web1, web2)`.

first_response!(ie, query::AbstractString, replicas::Tuple) =
    put!(ie, Julio.select(Events.fetch.(query .|> replicas)...))

# Google Search 3.0
# <https://talks.golang.org/2012/concurrency.slide#50>

function replicated_search(webs, images, videos)
    query = "Julio"
    results = String[]
    ih, oh = Julio.channel()
    open(oh) do oe
        Julio.withtaskgroup() do tg
            Julio.spawn!(first_response!, tg, ih, query, webs)
            Julio.spawn!(first_response!, tg, ih, query, images)
            Julio.spawn!(first_response!, tg, ih, query, videos)
            Julio.spawn!(tg) do
                Julio.sleep(0.08)
                Julio.cancel!(tg)
            end
            append!(results, oe)
            Julio.cancel!(tg)
        end
    end
    return results
end

# Setup code:

replicated_search_demo() = with_search_engines(replicated_search)

function with_close_hook(f)
    resources = []
    function closing(r)
        push!(resources, r)
        return r
    end
    try
        f(closing)
    finally
        foreach(close, resources)
    end
end

function spawn_fakesearch!(tg, label, closing)
    ih, oh = Julio.channel()
    ie = closing(open(ih))
    Julio.spawn!(tg, oh) do oe
        for (query, reply) in oe
            sleep(rand(0.01:0.01:0.1))
            reply[] = "$label result for $query"
        end
    end
    function request(query)
        reply = Julio.Promise()
        put!(ie, query => reply)
        return reply
    end
    return request
end

function with_search_engines(f)
    Julio.withtaskgroup() do tg
        with_close_hook() do closing
            web1 = spawn_fakesearch!(tg, "web1", closing)
            web2 = spawn_fakesearch!(tg, "web2", closing)
            image1 = spawn_fakesearch!(tg, "image1", closing)
            image2 = spawn_fakesearch!(tg, "image2", closing)
            video1 = spawn_fakesearch!(tg, "video1", closing)
            video2 = spawn_fakesearch!(tg, "video2", closing)
            f((web1, web2), (image1, image2), (video1, video2))
        end
    end
end

using Test

function test_replicated_search_demo()
    nok = 0
    for _ in 1:10
        results = replicated_search_demo()
        nok += length(results) == 3
    end
    @test nok > 0
end
