# Protocol definitions for runner-worker IPC.
# Included by both host (WorkerIPC.jl) and worker (WorkerIPC.jl in QuartoNotebookWorker).

# Wrapper to make any IO lockable for thread-safe writes
struct LockableIO{T<:IO}
    io::T
    lock::ReentrantLock
    LockableIO(io::T) where {T<:IO} = new{T}(io, ReentrantLock())
end

Base.lock(f, lio::LockableIO) =
    Base.lock(lio.lock) do
        f(lio.io)
    end

const MsgID = UInt64
const MAGIC = UInt32(0x514E5257)  # "QNRW"
const PROTOCOL_VERSION = UInt8(6)  # Separate notebook context key from source file

module MsgType
const CALL = 0x01       # expects response
const SHUTDOWN = 0x02   # graceful shutdown
const RESULT_OK = 0x80
const RESULT_ERR = 0x81
end

struct Message
    type::UInt8
    id::MsgID
    payload::Vector{UInt8}
end

# Connection handshake - worker writes, host reads
function write_handshake(lio::LockableIO)
    lock(lio) do socket
        write(socket, htol(MAGIC))
        write(socket, PROTOCOL_VERSION)
        flush(socket)
    end
    return nothing
end

function read_handshake(lio::LockableIO)
    io = lio.io
    magic = ltoh(read(io, UInt32))
    magic == MAGIC ||
        error("Invalid protocol magic: expected $(repr(MAGIC)), got $(repr(magic))")
    version = read(io, UInt8)
    version == PROTOCOL_VERSION ||
        error("Unsupported protocol version: $version (expected $PROTOCOL_VERSION)")
    return nothing
end

function write_message(lio::LockableIO, msg::Message)
    payload_len = UInt32(1 + sizeof(MsgID) + length(msg.payload))
    lock(lio) do socket
        write(socket, htol(payload_len))
        write(socket, msg.type)
        write(socket, htol(msg.id))
        write(socket, msg.payload)
        flush(socket)
    end
    return nothing
end

function read_message(lio::LockableIO)::Message
    io = lio.io
    payload_len = ltoh(read(io, UInt32))
    payload_len < 9 && error("Message too small: $payload_len bytes")
    payload_len > 1_000_000_000 && error("Message too large: $payload_len bytes")

    msg_type = read(io, UInt8)
    msg_id = ltoh(read(io, MsgID))

    data_len = Int(payload_len) - 1 - sizeof(MsgID)
    payload = read(io, data_len)

    return Message(msg_type, msg_id, payload)
end

# Minimal tagged binary serialization format
# Supports: Nothing, Bool, Int64, Float64, String, Symbol, Vector{UInt8}, Vector, Dict, Tuple, NamedTuple

const TAG_NOTHING = 0x00
const TAG_BOOL = 0x01
const TAG_INT64 = 0x02
const TAG_FLOAT64 = 0x03
const TAG_STRING = 0x04
const TAG_SYMBOL = 0x05
const TAG_BINARY = 0x06
const TAG_VECTOR = 0x07
const TAG_DICT = 0x08
const TAG_TUPLE = 0x09
const TAG_NAMEDTUPLE = 0x0A
const TAG_MIMERESULT = 0x0B
const TAG_CELLRESULT = 0x0C
const TAG_RENDERRESPONSE = 0x0D
const TAG_TYPED_DICT = 0x0E

# Request type tags
const TAG_MANIFEST_IN_SYNC_REQ = 0x20
const TAG_NOTEBOOK_INIT_REQ = 0x26
const TAG_NOTEBOOK_CLOSE_REQ = 0x27
const TAG_RENDER_REQ = 0x24
const TAG_EVALUATE_PARAMS_REQ = 0x25

# IPC data types for fully-typed deserialization

struct MimeResult
    mime::String
    error::Bool
    data::Vector{UInt8}
end

struct CellResult
    code::String
    cell_options::Dict{String,Any}
    results::Dict{String,MimeResult}
    display_results::Vector{Dict{String,MimeResult}}
    output::String
    error::Union{Nothing,String}
    backtrace::Vector{String}
end

struct RenderResponse
    cells::Vector{CellResult}
    is_expansion::Bool
end

# Request types for typed IPC dispatch

abstract type IPCRequest end

struct ManifestInSyncRequest <: IPCRequest end

Base.@kwdef struct NotebookInitRequest <: IPCRequest
    file::String                    # Absolute notebook path (context key)
    project::String
    options::Dict{String,Any}
    cwd::String
    env_vars::Vector{String}
end

Base.@kwdef struct NotebookCloseRequest <: IPCRequest
    file::String
end

Base.@kwdef struct RenderRequest <: IPCRequest
    code::String
    file::String
    notebook::String
    line::Int64
    cell_options::Dict{String,Any}
    inline::Bool = false
end

Base.@kwdef struct EvaluateParamsRequest <: IPCRequest
    file::String                    # Identifies notebook context
    params::Dict{String,Any}
end

# Response type mapping for type-stable returns
response_type(::Type{ManifestInSyncRequest}) = Union{Nothing,String}
response_type(::Type{NotebookInitRequest}) = Nothing
response_type(::Type{NotebookCloseRequest}) = Nothing
response_type(::Type{RenderRequest}) = RenderResponse
response_type(::Type{EvaluateParamsRequest}) = Nothing

function _serialize(io::IO, ::Nothing)
    write(io, TAG_NOTHING)
end

function _serialize(io::IO, x::Bool)
    write(io, TAG_BOOL, UInt8(x))
end

function _serialize(io::IO, x::Int64)
    write(io, TAG_INT64)
    write(io, htol(x))
end

function _serialize(io::IO, x::Integer)
    _serialize(io, Int64(x))
end

function _serialize(io::IO, x::Float64)
    write(io, TAG_FLOAT64)
    write(io, htol(x))
end

function _serialize(io::IO, x::AbstractFloat)
    _serialize(io, Float64(x))
end

function _serialize(io::IO, x::String)
    write(io, TAG_STRING)
    write(io, htol(UInt32(sizeof(x))))
    write(io, x)
end

function _serialize(io::IO, x::Symbol)
    s = String(x)
    write(io, TAG_SYMBOL)
    write(io, htol(UInt32(sizeof(s))))
    write(io, s)
end

function _serialize(io::IO, x::Vector{UInt8})
    write(io, TAG_BINARY)
    write(io, htol(UInt32(length(x))))
    write(io, x)
end

function _serialize(io::IO, x::AbstractVector)
    write(io, TAG_VECTOR)
    write(io, htol(UInt32(length(x))))
    for v in x
        _serialize(io, v)
    end
end

function _serialize(io::IO, x::AbstractDict)
    write(io, TAG_DICT)
    write(io, htol(UInt32(length(x))))
    for (k, v) in x
        _serialize(io, String(k))  # keys as strings
        _serialize(io, v)
    end
end

function _serialize(io::IO, x::Tuple)
    write(io, TAG_TUPLE)
    write(io, htol(UInt32(length(x))))
    for v in x
        _serialize(io, v)
    end
end

function _serialize(io::IO, x::NamedTuple)
    write(io, TAG_NAMEDTUPLE)
    write(io, htol(UInt32(length(x))))
    for (k, v) in pairs(x)
        _serialize(io, k)
        _serialize(io, v)
    end
end

# Typed Dict serialization for Dict{String,MimeResult}
function _serialize(io::IO, x::Dict{String,MimeResult})
    write(io, TAG_TYPED_DICT, TAG_MIMERESULT)
    write(io, htol(UInt32(length(x))))
    for (k, v) in x
        _serialize(io, k)
        _serialize(io, v)
    end
end

function _serialize(io::IO, x::MimeResult)
    write(io, TAG_MIMERESULT)
    _serialize(io, x.mime)
    _serialize(io, x.error)
    _serialize(io, x.data)
end

function _serialize(io::IO, x::CellResult)
    write(io, TAG_CELLRESULT)
    _serialize(io, x.code)
    _serialize(io, x.cell_options)
    _serialize(io, x.results)
    _serialize(io, x.display_results)
    _serialize(io, x.output)
    _serialize(io, x.error)
    _serialize(io, x.backtrace)
end

function _serialize(io::IO, x::RenderResponse)
    write(io, TAG_RENDERRESPONSE)
    _serialize(io, x.cells)
    _serialize(io, x.is_expansion)
end

# Request type serialization
function _serialize(io::IO, ::ManifestInSyncRequest)
    write(io, TAG_MANIFEST_IN_SYNC_REQ)
end

function _serialize(io::IO, x::NotebookInitRequest)
    write(io, TAG_NOTEBOOK_INIT_REQ)
    _serialize(io, x.file)
    _serialize(io, x.project)
    _serialize(io, x.options)
    _serialize(io, x.cwd)
    _serialize(io, x.env_vars)
end

function _serialize(io::IO, x::NotebookCloseRequest)
    write(io, TAG_NOTEBOOK_CLOSE_REQ)
    _serialize(io, x.file)
end

function _serialize(io::IO, x::RenderRequest)
    write(io, TAG_RENDER_REQ)
    _serialize(io, x.code)
    _serialize(io, x.file)
    _serialize(io, x.notebook)
    _serialize(io, x.line)
    _serialize(io, x.cell_options)
    _serialize(io, x.inline)
end

function _serialize(io::IO, x::EvaluateParamsRequest)
    write(io, TAG_EVALUATE_PARAMS_REQ)
    _serialize(io, x.file)
    _serialize(io, x.params)
end

function _ipc_serialize(data)::Vector{UInt8}
    buf = IOBuffer()
    _serialize(buf, data)
    take!(buf)
end

function _deserialize(io::IO)
    tag = read(io, UInt8)
    if tag == TAG_NOTHING
        nothing
    elseif tag == TAG_BOOL
        read(io, UInt8) != 0
    elseif tag == TAG_INT64
        ltoh(read(io, Int64))
    elseif tag == TAG_FLOAT64
        ltoh(read(io, Float64))
    elseif tag == TAG_STRING
        len = ltoh(read(io, UInt32))
        String(read(io, len))
    elseif tag == TAG_SYMBOL
        len = ltoh(read(io, UInt32))
        Symbol(String(read(io, len)))
    elseif tag == TAG_BINARY
        len = ltoh(read(io, UInt32))
        read(io, len)
    elseif tag == TAG_VECTOR
        len = ltoh(read(io, UInt32))
        [_deserialize(io) for _ = 1:len]
    elseif tag == TAG_DICT
        len = ltoh(read(io, UInt32))
        Dict{String,Any}(String(_deserialize(io)) => _deserialize(io) for _ = 1:len)
    elseif tag == TAG_TUPLE
        len = ltoh(read(io, UInt32))
        Tuple(_deserialize(io) for _ = 1:len)
    elseif tag == TAG_NAMEDTUPLE
        len = ltoh(read(io, UInt32))
        keys = Symbol[]
        vals = Any[]
        for _ = 1:len
            push!(keys, _deserialize(io))
            push!(vals, _deserialize(io))
        end
        NamedTuple{Tuple(keys)}(Tuple(vals))
    elseif tag == TAG_MIMERESULT
        MimeResult(_deserialize(io), _deserialize(io), _deserialize(io))
    elseif tag == TAG_CELLRESULT
        CellResult(
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
        )
    elseif tag == TAG_RENDERRESPONSE
        RenderResponse(_deserialize(io), _deserialize(io))
    elseif tag == TAG_TYPED_DICT
        value_type = read(io, UInt8)
        len = ltoh(read(io, UInt32))
        if value_type == TAG_MIMERESULT
            Dict{String,MimeResult}(_deserialize(io) => _deserialize(io) for _ = 1:len)
        else
            Dict{String,Any}(_deserialize(io) => _deserialize(io) for _ = 1:len)
        end
    elseif tag == TAG_MANIFEST_IN_SYNC_REQ
        ManifestInSyncRequest()
    elseif tag == TAG_NOTEBOOK_INIT_REQ
        NotebookInitRequest(
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
        )
    elseif tag == TAG_NOTEBOOK_CLOSE_REQ
        NotebookCloseRequest(_deserialize(io))
    elseif tag == TAG_RENDER_REQ
        RenderRequest(
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
            _deserialize(io),
        )
    elseif tag == TAG_EVALUATE_PARAMS_REQ
        EvaluateParamsRequest(_deserialize(io), _deserialize(io))
    else
        error("Unknown serialization tag: $tag")
    end
end

function _ipc_deserialize(bytes::Vector{UInt8})
    _deserialize(IOBuffer(bytes))
end
