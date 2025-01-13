
const MsgType = (
    from_host_call_with_response = UInt8(1),
    from_host_call_without_response = UInt8(2),
    from_host_fake_interrupt = UInt8(20),
    ####
    from_worker_call_result = UInt8(80),
    from_worker_call_failure = UInt8(81),
    ###
    special_serialization_failure = UInt8(100),
    special_worker_terminated = UInt8(101),
)

const MsgID = UInt64

const BUFFER_SIZE = 65536 # Base.SZ_UNBUFFERED_IO
# Future-compat version of Base.buffer_writes
_buffer_writes(io) = @static if isdefined(Base, :buffer_writes) &&
           hasmethod(Base.buffer_writes, (Base.LibuvStream, Int))
    Base.buffer_writes(io, BUFFER_SIZE)
end

# from Distributed.jl:
#
# Boundary inserted between messages on the wire, used for recovering
# from deserialization errors. Picked arbitrarily.
# A size of 10 bytes indicates ~ ~1e24 possible boundaries, so chance of collision
# with message contents is negligible.
const MSG_BOUNDARY = UInt8[0x79, 0x8e, 0x8e, 0xf5, 0x6e, 0x9b, 0x2e, 0x97, 0xd5, 0x7d]



function _discard_until_boundary(io::IO)
    readuntil(io, MSG_BOUNDARY)
end

function _serialize_msg(io::IO, msg_type::UInt8, msg_id::MsgID, msg_data::Any)
    lock(io)
    try
        write(io, msg_type)
        write(io, msg_id)
        Base.invokelatest(BSON.bson, io, Dict{Symbol,Any}(:data => msg_data))
        write(io, MSG_BOUNDARY)
        flush(io)
    finally
        unlock(io)
    end

    return nothing
end
