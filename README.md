# QuartoNotebookRunner

[![CI](https://github.com/PumasAI/QuartoNotebookRunner.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/PumasAI/QuartoNotebookRunner.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/PumasAI/QuartoNotebookRunner.jl/graph/badge.svg?token=84nO9FG9oc)](https://codecov.io/gh/PumasAI/QuartoNotebookRunner.jl)

> [!NOTE]
>
> This Julia package provides a code evaluation engine that Quarto
> can use. Please run the `quarto` CLI tool rather than this package
> directly unless you would like to help with the development of this engine.
>
> Starting from the **pre-release** [`v1.5.29`](https://github.com/quarto-dev/quarto-cli/releases/tag/v1.5.29)
> this engine is available out-of-the-box with `quarto` when you set `engine: julia` in
> your Quarto notebook files. You don't need to follow the developer instructions
> below.

## Developer Documentation

This Julia package can run [Quarto](https://quarto.org) notebooks containing Julia code and save the
results to Jupyter notebooks. These intermediate `.ipynb` files can then be passed to `quarto render`
for final rendering to a multitude of different output formats.

### Installation

Install this package into an isolated named environment rather than your global
environment so that it does not interact with any other packages.

```
julia --project=@quarto -e 'import Pkg; Pkg.add("QuartoNotebookRunner")'
```

### Usage

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

### Daemon mode

Start the socket server with:

```
julia --project=@quarto -e 'import QuartoNotebookRunner; QuartoNotebookRunner.serve(; port = 1234)'
```

and then interact with it via the JSON API from any other language. See `test/client.js` for an example.

### Source code structure

The source for this package is split into two distinct parts.

#### `QuartoNotebookRunner`

The `QuartoNotebookRunner` package is what users install themselves (or have
installed via `quarto`). This package manages the parsing of Quarto notebooks,
passing of parsed code blocks to the worker processes that run the code in
isolation, as well as communicating with the `quarto` process that requests the
rendering of a notebook.

#### `QuartoNotebookWorker`

The `QuartoNotebookWorker` package, located at `src/QuartoNotebookWorker`, is a
"local" package that is loaded into every worker process that runs a notebook.
This worker package has no dependencies outside of the standard library.

There are several external package dependencies that are used by this worker
package, but the code for them is vendored dynamically into the worker package,
rather than being added as external dependencies. This avoids a user potentially
running into conflicting versions of packages should they require a different
version.

To debug issues within the worker package you can directly run a REPL with it
loaded rather than having to create a notebook and run code through it. Use the
following to import `QuartoNotebookWorker` in a REPL session:

```
julia> using QuartoNotebookRunner # Load the runner package.

julia> QuartoNotebookRunner.WorkerSetup.debug() # Start a subprocess with the worker package loaded.
```

A new Julia REPL will start *inside* of the current one.

```
julia> QuartoNotebookWorker.<tab> # Access the worker package.
```

Use `ctrl-d` (or `exit()`) to exit the worker REPL and return to the main REPL.

If you have `Revise`, `TestEnv`, or `Debugger` available within your global
environment then those will be loaded into the interactive worker process as
well to aid in debugging. Editing code within the `src/QuartoNotebookWorker`
folder will reflect the changes in the REPL via `Revise` in the normal way.

### Adding package "integrations"

Some packages require custom integrations to be written to make them behave as
expected within the worker processes that run notebooks. For example, `Plots.jl`
requires a custom integration to work correctly with `quarto`'s image format and
dimension settings.

This is achieved by using Julia's native package extension mechanism. You can
find all the current package integrations in the `src/QuartoNotebookWorker/ext`
folder. Typically this is done via adding function hooks within the `__init__`
method of the extension that run at different points during notebook execution.
