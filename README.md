# QuartoNotebookRunner

Run [Quarto](https://quarto.org) notebooks containing Julia code and save the
results to Jupyter notebooks.

## Installation

Install this package into an isolated named environment rather than your global
environment so that it does not interact with any other packages.

```
julia --project=@quarto -e 'import Pkg; Pkg.add("QuartoNotebookRunner")'
```

## Usage

```
julia --project=@quarto
```

```julia
julia> using QuartoNotebookRunner

julia> server = QuartoNotebookRunner.Server();

julia> QuartoNotebookRunner.run!(server, "notebook.qmd"; output = "notebook.ipynb")

julia> QuartoNotebookRunner.close!(server, "notebook.qmd")

```

Notebooks are run in isolated Julia processes. The first call to `run!` for each
notebook will start a new Julia process. Subsequent `run!`s will reuse the same
process for each notebook. The process will be closed when `close!` is called.

Each `run!` of a notebook will evaluate code blocks in a new Julia `Module` so
that struct definitions and other global constants can be redefined between
runs. Non-constant globals are GC'd between runs to avoid memory leaks.

Note that no caching is implemented, or any form of reactive evaluation.

## Daemon mode

Start the socket server with:

```
julia --project=@quarto -e 'import QuartoNotebookRunner; QuartoNotebookRunner.serve(; port = 1234)'
```

and then interact with it via the JSON API from any other language. See `test/client.js` for an example.
