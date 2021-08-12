struct MSQNode{T,R}
    next::R
    data::T
    # Node{T,R}() = new{T,R}()
    MSQNode{T,R}(next) where {T,R} = new{T,R}(next)
    MSQNode{T,R}(next, data) where {T,R} = new{T,R}(next, data)
end

const MSQNodeRef{T} = Reagents.Ref{Union{Nothing,MSQNode{T}}}
const MSQHeadRef{T} = Reagents.Ref{MSQNode{T}}

MSQNode(next::MSQNodeRef{T}) where {T} = MSQNode{T,typeof(next)}(next)
MSQNode(next::MSQNodeRef{T}, data) where {T} = MSQNode{T,typeof(next)}(next, data)

struct MSQueue{T,R<:MSQHeadRef{T}}
    head::R
    tail::R
    function MSQueue{T}() where {T}
        node = MSQNode(MSQNodeRef{T}(nothing))
        head = MSQHeadRef{T}(node)
        tail = MSQHeadRef{T}(node)
        return new{T,typeof(head)}(head, tail)
    end
end

nodetype(::MSQueue{<:Any,R}) where {N,R<:Reagents.Ref{N}} = N

Base.eltype(::Type{<:MSQueue{T}}) where {T} = T

Base.isempty(q::MSQueue) = q.head[].next[] === nothing

trypoppingfirst(q::MSQueue{T}) where {T} =
    Reagents.Update(q.head) do node, _
        next = node.next[]
        if next === nothing
            (node, nothing)
        else
            next::nodetype(q)
            (next, Some(next.data))
        end
    end

pushing(q::MSQueue{T}) where {T} =
    Reagents.Computed() do x
        node = MSQNode(MSQNodeRef{T}(nothing), x)
        while true
            tail = q.tail[]
            tail::nodetype(q)
            next = tail.next[]
            if next === nothing  # found the tail
                return Reagents.CAS(tail.next, nothing, node) ⨟ Reagents.PostCommit() do _
                    Reagents.try!(Reagents.CAS(q.tail, tail, node))
                end
            else  # need the fixup
                next::nodetype(q)
                Reagents.try!(Reagents.CAS(q.tail, tail, next))
            end
        end
    end
