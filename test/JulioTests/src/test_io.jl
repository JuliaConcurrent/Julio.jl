module TestIO

using Julio
using Test

function test_io_read()
    text = """
    line 1
    line 2
    """
    iobuf = IOBuffer(text)
    Julio.open(iobuf) do io
        @test read(io, String) == text
    end

    iobuf = IOBuffer(text)
    Julio.open(iobuf) do io
        @test readline(io) == "line 1"
        @test readline(io; keep = true) == "line 2\n"
    end
end

function test_io_write()
    iobuf = IOBuffer()
    Julio.open(iobuf) do io
        write(io, "hello")
    end
    @test String(take!(iobuf)) == "hello"
end

function test_io_read_cat()
    try
        read(`cat`)
    catch
        return @test_skip false
    end
    read_finished = Ref(false)
    output = Pipe()
    input = Pipe()
    proc = run(pipeline(`cat`; stdout = output, stdin = input); wait = false)
    close(output.in)
    ans1 = ans2 = :__notset__
    try
        Julio.open(output) do io
            write(input, "hello")
            flush(input)
            ans1 = Julio.withtimeout(0.1) do
                readline(io)
                read_finished[] = true
            end
            write(input, "\nworld")
            close(input)
            ans2 = Julio.withtimeout(60) do
                read(io, String)
            end
        end
    finally
        close(input)
        close(output)
        wait(proc)
    end
    @test ans1 === nothing
    @test !read_finished[]
    @test something(ans2) == "hello\nworld"
end

function test_open_cmd()
    Julio.open(`echo "hello"`) do output
        @test read(output, String) == "hello\n"
    end
    Julio.open(`echo "hello"`) do output
        @test readline(output) == "hello"
    end
    Julio.open(`echo "hello"`) do output
        @test readline(output; keep = true) == "hello\n"
    end
end

end  # module
