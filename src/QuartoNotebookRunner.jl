"""
Run, and re-run, Quarto notebooks and convert the results to Jupyter notebook files.

# Usage

```julia
julia> using QuartoNotebookRunner

julia> server = QuartoNotebookRunner.Server();

julia> QuartoNotebookRunner.run!(server, "notebook.qmd", output = "notebook.ipynb")

julia> QuartoNotebookRunner.close!(server, "notebook.qmd")

```
"""
module QuartoNotebookRunner

# Imports.

import BSON
import Base64
import CommonMark
import Compat
import Dates
import InteractiveUtils
import IterTools
import JSON3
import Logging
import PrecompileTools
import Preferences
import ProgressLogging
import REPL
import Random
import Sockets
import SHA
import TOML
import YAML

# Exports.

export Server, render, run!, close!

# Includes.

include("UserError.jl")
include("Malt.jl")
include("WorkerSetup.jl")
include("server.jl")
include("socket.jl")
include("worker.jl")
include("utilities.jl")
include("precompile.jl")

end # module QuartoNotebookRunner
