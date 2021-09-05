struct TSNode{T}
    head::T
    tail::Union{TSNode{T},Nothing}
end

const TSList{T} = Union{TSNode{T},Nothing}

struct TreiberStack{T,Ref<:Reagents.Ref{TSList{T}}}
    head::Ref
end

TreiberStack{T}() where {T} = TreiberStack(Reagents.Ref{TSList{T}}(nothing))

Base.eltype(::Type{<:TreiberStack{T}}) where {T} = T
Base.isempty(stack::TreiberStack) = stack.head[] === nothing

pushing(stack::TreiberStack{T}) where {T} =
    Update((xs, x) -> (TSNode{T}(x, xs), nothing), stack.head)

trypopping(stack::TreiberStack) =
    Update(stack.head) do xs, _ignored
        if xs === nothing
            return (nothing, nothing)
        else
            return (xs.tail, Some(xs.head))
        end
    end

Base.push!(stack::TreiberStack, x) = pushing(stack)(convert(eltype(stack), x))
maybepop_nowait!(stack::TreiberStack) = trypopping(stack)()

Base.IteratorSize(::Type{<:TreiberStack}) = Base.SizeUnknown()
function Base.iterate(stack::TreiberStack, list = stack.head[])
    node = @something(list, return nothing)
    return (node.head, node.tail)
end
