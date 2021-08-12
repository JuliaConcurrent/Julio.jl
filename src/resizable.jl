
struct ResizableViewVector{T,Data<:AbstractVector{T}} <: AbstractVector{T}
    data::Data
    offset::Int
end

function resizableview(data::AbstractVector, offset::Integer)
    @argcheck firstindex(data) - 1 <= offset <= lastindex(data)
    return ResizableViewVector(data, offset)
end

resizabletail(data::AbstractVector) = resizableview(data, lastindex(data))

Base.size(xs::ResizableViewVector) = (length(xs.data) - xs.offset,)

Base.@propagate_inbounds Base.getindex(xs::ResizableViewVector, i::Int) =
    xs.data[xs.offset+i]

Base.@propagate_inbounds Base.setindex!(xs::ResizableViewVector, x, i::Int) =
    xs.data[xs.offset+i] = x

function Base.resize!(xs::ResizableViewVector, n::Integer)
    resize!(xs.data, xs.offset + n)
    return xs
end

function Base.push!(xs::ResizableViewVector, x)
    push!(xs.data, x)
    return xs
end
