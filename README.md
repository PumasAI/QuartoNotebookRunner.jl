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

## Features

### Expandable cells

Executable julia cells that contain the option `#| expand: true` have special behavior defined.
QuartoNotebookRunner expects such cells to return an iterable collection of objects with a mandatory
`thunk` field and two optional `code` and `options` fields.

The `thunk` should contain a function that represents the lazily computed output of a "fake" code cell.
Such a code cell is "fake" in the sense that it is not present in the original markdown source, and because its own "code" (which can
optionally be set via the `code` field) is never executed. However, by having the option of making one
code cell's output expand into multiple fake code cells plus their outputs, you have the freedom of
dynamically generating parts of a quarto notebook that would otherwise have to be hardcoded.
One example where this can be useful is quarto's tabset feature which groups multiple sections into tabs.

Here is one simple example where a cell creates two expanded "fake" cells. We can use the `options` field
to set cell options like `echo` or `output` which allows us to hide code and use outputs as markdown.

````markdown
---
engine: julia
---

```{julia}
#| expand: true

[
    (;
        thunk = () -> println(
            "This thunk's _stdout_ is treated as **markdown** ",
            "because of the `output: asis` option.\n\n",
            "::: {.callout-note}\n",
            "The fake code cell is hidden with `echo: false`\n",
            ":::",
        ),
        options = Dict("echo" => false, "output" => "asis")),
    (;
        thunk = () -> 456,
        code = """
        # fake code that is not actually executed
        456
        """
    ),
]
```
````

Which results in this output when rendered to HTML with quarto:

<img width="600" alt="image" src="https://github.com/PumasAI/QuartoNotebookRunner.jl/assets/22495855/bf821a24-aa6d-42c0-900e-c08af8739325">


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
