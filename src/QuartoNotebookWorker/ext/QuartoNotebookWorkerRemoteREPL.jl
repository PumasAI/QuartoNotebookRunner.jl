module QuartoNotebookWorkerRemoteREPL

import QuartoNotebookWorker
import RemoteREPL
import RemoteREPL.Sockets

const SERVER = Ref{Sockets.TCPServer}()

function QuartoNotebookWorker._remote_repl(::Nothing, port)
    address = Sockets.localhost
    new_port = something(port, RemoteREPL.DEFAULT_PORT)
    if isassigned(SERVER)
        server = SERVER[]
        _, current_port = Sockets.getsockname(server)
        current_port = Int(current_port)
        if new_port == current_port
            @info "REPL server currently running." current_port
            return current_port
        else
            @info "closing previous REPL server." current_port
            close(server)
        end
    end
    @info "starting new REPL server." new_port
    SERVER[] = server = Sockets.listen(address, new_port)
    @async RemoteREPL.serve_repl(server)
    return new_port
end

end
