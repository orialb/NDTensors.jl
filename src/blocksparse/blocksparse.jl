export BlockSparse,
       BlockSparseTensor,
       Block,
       block,
       BlockOffset,
       BlockOffsets,
       blockoffsets,
       blockview,
       nnzblocks,
       nnz,
       findblock,
       isblocknz

#
# BlockSparse storage
#

struct BlockSparse{ElT,VecT,N} <: TensorStorage{ElT}
  data::VecT
  blockoffsets::BlockOffsets{N}  # Block number-offset pairs
  function BlockSparse(data::VecT,
                       blockoffsets::BlockOffsets{N};
                       sorted=true) where {VecT<:AbstractVector{ElT},
                                           N} where {ElT}
    sorted && check_blocks_sorted(blockoffsets)
    new{ElT,VecT,N}(data, blockoffsets)
  end
end

function BlockSparse(::Type{ElT},
                     blockoffsets::BlockOffsets,
                     dim::Integer;
                     vargs...) where {ElT<:Number}
  return BlockSparse(zeros(ElT, dim), blockoffsets; vargs...)
end

function BlockSparse(::Type{ElT},
                     ::UndefInitializer,
                     blockoffsets::BlockOffsets,
                     dim::Integer; vargs...) where {ElT<:Number}
  return BlockSparse(Vector{ElT}(undef,dim),blockoffsets; vargs...)
end

BlockSparse(blockoffsets::BlockOffsets,
            dim::Integer; vargs...) = BlockSparse(Float64,blockoffsets,dim; vargs...)

BlockSparse(::UndefInitializer,
            blockoffsets::BlockOffsets,
            dim::Integer; vargs...) = BlockSparse(Float64,undef,blockoffsets,dim; vargs...)

#
# Random
#

function Base.randn(::Type{ <: BlockSparse{ElT}},
                    blockoffsets::BlockOffsets,
                    dim::Integer) where {ElT <: Number}
  return BlockSparse(randn(ElT, dim), blockoffsets)
end

#function BlockSparse{ElR}(data::VecT,offsets) where {ElR,VecT<:AbstractVector{ElT}} where {ElT}
#  ElT == ElR ? BlockSparse(data,offsets) : BlockSparse(ElR.(data),offsets)
#end
#BlockSparse{ElT}() where {ElT} = BlockSparse(ElT[],BlockOffsets())

function Base.similar(D::BlockSparse)
  return BlockSparse(similar(data(D)),blockoffsets(D))
end

# TODO: test this function
Base.similar(D::BlockSparse,
             ::Type{ElT}) where {ElT} = BlockSparse(similar(data(D),ElT),
                                                    copy(blockoffsets(D)))
Base.copy(D::BlockSparse) = BlockSparse(copy(data(D)),
                                        copy(blockoffsets(D)))

# TODO: check the offsets are the same?
function Base.copyto!(D1::BlockSparse,D2::BlockSparse)
  blockoffsets(D1) ≠ blockoffsets(D1) && error("Cannot copy between BlockSparse storages with different offsets")
  copyto!(data(D1),data(D2))
  return D1
end

# convert to complex
# TODO: this could be a generic TensorStorage function
Base.complex(D::BlockSparse{T}) where {T} = BlockSparse{complex(T)}(complex(data(D)),
                                                                    blockoffsets(D))

function Base.conj(D::BlockSparse{<: Real}; always_copy = false) 
  if always_copy
    return copy(D)
  end
  return D
end

function Base.conj(D::BlockSparse; always_copy = false)
  if always_copy
    return conj!(copy(D))
  end
  return BlockSparse(conj(data(D)), blockoffsets(D))
end



function scale!(D::BlockSparse,α::Number)
  scale!(data(D),α)
  return D
end

Base.ndims(::BlockSparse{T,V,N}) where {T,V,N} = N

Base.eltype(::BlockSparse{T}) where {T} = eltype(T)
# This is necessary since for some reason inference doesn't work
# with the more general definition (eltype(Nothing) === Any)
Base.eltype(::BlockSparse{Nothing}) = Nothing
Base.eltype(::Type{BlockSparse{T}}) where {T} = eltype(T)

dense(::Type{<:BlockSparse{ElT,VecT}}) where {ElT,VecT} = Dense{ElT,VecT}

function Base.promote_rule(::Type{<:BlockSparse{ElT1,VecT1,N}},
                           ::Type{<:BlockSparse{ElT2,VecT2,N}}) where {ElT1,ElT2,VecT1,VecT2,N}
  return BlockSparse{promote_type(ElT1,ElT2),promote_type(VecT1,VecT2),N}
end

function Base.promote_rule(::Type{<:BlockSparse{ElT1,VecT1,N1}},
                           ::Type{<:BlockSparse{ElT2,VecT2,N2}}) where {ElT1,ElT2,VecT1,VecT2,N1,N2}
  return BlockSparse{promote_type(ElT1,ElT2),promote_type(VecT1,VecT2),NR} where {NR}
end

function Base.promote_rule(::Type{<:BlockSparse{ElT1,Vector{ElT1},N1}},
                           ::Type{ElT2}) where {ElT1,ElT2<:Number,N1}
  ElR = promote_type(ElT1,ElT2)
  VecR = Vector{ElR}
  return BlockSparse{ElR,VecR,N1}
end

function Base.convert(::Type{<:BlockSparse{ElR,VecR,N}},
                      D::BlockSparse{ElD,VecD,N}) where {ElR,VecR,N,ElD,VecD}
  return BlockSparse(convert(VecR,data(D)),
                     blockoffsets(D))
end

function Base.:*(D::BlockSparse,x::Number)
  return BlockSparse(x*data(D),blockoffsets(D))
end
Base.:*(x::Number,D::BlockSparse) = D*x

"""
blockdim(T::BlockSparse,pos::Int)

Get the block dimension of the block at position pos.
"""
blockdim(D::BlockSparse,
         pos::Int) = blockdim(blockoffsets(D),
                              nnz(D),
                              pos)

"""
blockdim(T::BlockSparse,block::Block)

Get the block dimension of the block.
"""
function blockdim(D::BlockSparse,
                  block::Block)
  pos = findblock(D, block)
  return blockdim(D, pos)
end

findblock(D::BlockSparse{<:Number,
                         <:AbstractVector,
                         N},
          block::Block{N};
          vargs...) where {N} = findblock(blockoffsets(D),
                                          block;
                                          vargs...)

"""
isblocknz(T::BlockSparse,
          block::Block)

Check if the specified block is non-zero.
"""
function isblocknz(T::BlockSparse{ElT,VecT,N},
                   block::Block{N}) where {ElT,VecT,N}
  isnothing(findblock(T,block)) && return false
  return true
end

# Given a specified block, return a Dense storage that is a view to the data
# in that block. Return nothing if the block is structurally zero
function blockview(T::BlockSparse,
                   block)
  #error("Block must be structurally non-zero to get a view")
  !isblocknz(T,block) && return nothing
  blockoffsetT = offset(T,block)
  blockdimT = blockdim(T,block)
  dataTslice = @view data(T)[blockoffsetT+1:blockoffsetT+blockdimT]
  return Dense(dataTslice)
end

function Base.:+(D1::BlockSparse,D2::BlockSparse)
  # This could be of order nnzblocks, avoid?
  if blockoffsets(D1) == blockoffsets(D2)
    return BlockSparse(data(D1)+data(D2),blockoffsets(D1))
  end
  blockoffsetsR,nnzR = union(blockoffsets(D1),nnz(D1),
                             blockoffsets(D2),nnz(D2))
  R = BlockSparse(undef,blockoffsetsR,nnzR)
  for (blockR,offsetR) in blockoffsets(R)
    blockview1 = blockview(D1,blockR)
    blockview2 = blockview(D2,blockR)
    blockviewR = blockview(R,blockR)
    if isnothing(blockview1)
      copyto!(blockviewR,blockview2)
    elseif isnothing(blockview2)
      copyto!(blockviewR,blockview1)
    else
      # TODO: is this fast?
      blockviewR .= blockview1 .+ blockview2
    end
  end
  return R
end


# Helper function for HDF5 write/read of BlockSparse
function offsets_to_array(boff::BlockOffsets{N}) where {N}
  nblocks = length(boff)
  asize = (N+1)*nblocks
  n = 1
  a = Vector{Int}(undef,asize)
  for bo in boff
    for j=1:N
      a[n] = bo[1][j]
      n += 1
    end
    a[n] = bo[2]
    n += 1
  end
  return a
end

# Helper function for HDF5 write/read of BlockSparse
function array_to_offsets(a,N::Int)
  asize = length(a)
  nblocks = div(asize,N+1)
  boff = BlockOffsets{N}(undef,nblocks)
  j = 0
  for b=1:nblocks
    boff[b] = Pair( ntuple(i->(a[j+i]),N) , a[j+N+1] )
    j += (N+1)
  end
  return boff
end

function HDF5.write(parent::Union{HDF5File, HDF5Group},
                    name::String,
                    B::BlockSparse)
  g = g_create(parent,name)
  attrs(g)["type"] = "BlockSparse{$(eltype(B))}"
  attrs(g)["version"] = 1
  if eltype(B) != Nothing
    write(g,"ndims",ndims(B))
    write(g,"data",data(B))
    off_array = offsets_to_array(blockoffsets(B))
    write(g,"offsets",off_array)
  end
end

function HDF5.read(parent::Union{HDF5File,HDF5Group},
                   name::AbstractString,
                   ::Type{Store}) where {Store <: BlockSparse}
  g = g_open(parent,name)
  ElT = eltype(Store)
  typestr = "BlockSparse{$ElT}"
  if read(attrs(g)["type"]) != typestr
    error("HDF5 group or file does not contain $typestr data")
  end
  N = read(g,"ndims")
  data = read(g,"data")
  off_array = read(g,"offsets")
  boff = array_to_offsets(off_array,N)
  return BlockSparse(data,boff)
end

