struct UserError <: Exception
    msg::String
end

function Base.showerror(io::IO, e::UserError)
    print(io, e.msg)
end
