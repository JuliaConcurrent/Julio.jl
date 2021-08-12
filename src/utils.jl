mutable struct RelaxedRef{T}
    @atomic value::T
    RelaxedRef{T}() where {T} = new{T}()
    RelaxedRef{T}(value) where {T} = new{T}(value)
end

Base.getindex(ref::RelaxedRef) = @atomic :monotonic ref.value

function Base.setindex!(ref::RelaxedRef{T}, value) where {T}
    value = convert(T, value)
    @atomic :monotonic ref.value = value
end

# Use a better algorithm?
# https://en.wikipedia.org/wiki/String-searching_algorithm
function has_subseq(seq::AbstractVector{T}, sub::AbstractVector{T}) where {T}
    for i in firstindex(seq):lastindex(seq)-length(sub)
        d = 0
        for j in eachindex(sub)
            if !(@inbounds isequal(seq[i+d], sub[j]))
                @goto failed
            end
            d += 1
        end
        return true
        @label failed
    end
    return false
end
