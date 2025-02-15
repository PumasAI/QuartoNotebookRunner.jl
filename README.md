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
> your Quarto Markdown files. You don't need to follow the developer instructions below. Note, however, the following Quarto upstream issues.
>
> #### [Scripts with the percent format](https://github.com/quarto-dev/quarto-cli/issues/10034)
> QuartoNotebookRunner can process Julia scripts annotated with the [percent format](https://jupytext.readthedocs.io/en/latest/formats-scripts.html#the-percent-format) (see this [`test file`](test/examples/cell_types.jl) for an example). However, at the moment, Quarto [mistakenly assigns the Jupyter engine](https://github.com/quarto-dev/quarto-cli/issues/10034#issuecomment-2174251544) as soon as the percent format is detected, even if the Julia engine is explicitly set in the script header. A somewhat unsatisfactory workaround is to move the code of interest to a Quarto Markdown file. Alternatively, it is still possible to render individual Julia scripts using QuartoNotebookRunner directly, as described in the [Usage](#usage) section below. Quarto projects including Julia scripts can not be rendered until the upstream issue is resolved.
>
> #### [Project-wide engine](https://github.com/quarto-dev/quarto-cli/issues/3157)
> If you are working with [Quarto Projects](https://quarto.org/docs/projects/quarto-projects.html), be aware that Quarto is failing to set the project-wide engine given in the `_quarto.yml` project file. A simple workaround is to set the Julia engine in each Quarto Markdown file of your project.

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

You can also start up a remote REPL connection to an already running notebook
process using [`RemoteREPL.jl`](https://github.com/JuliaWeb/RemoteREPL.jl).
Import `RemoteREPL` into a notebook cell and run
`Main.QuartoNotebookWorker.remote_repl()`. Then in a separate REPL run
`RemoteREPL.connect_repl()` to connect to the notebook process for debugging.

### Adding package "integrations"

Some packages require custom integrations to be written to make them behave as
expected within the worker processes that run notebooks. For example, `Plots.jl`
requires a custom integration to work correctly with `quarto`'s image format and
dimension settings.

This is achieved by using Julia's native package extension mechanism. You can
find all the current package integrations in the `src/QuartoNotebookWorker/ext`
folder. Typically this is done via adding function hooks within the `__init__`
method of the extension that run at different points during notebook execution.

### Package Extensions

As discussed above `QuartoNotebookWorker` is implemented as a full Julia package
rather than just a `Module` loaded into the worker processes. This allows for
any package to extend the functionality provided by the worker. To do this make
use `Requires.jl` (or the mechanism that it leverages) to load extension code
that requires `QuartoNotebookWorker`.

```julia
function __init__()
    @require QuartoNotebookWorker="38328d9c-a911-4051-bc06-3f7f556ffeda" include("extension.jl")
end
```

With this addition whenever `PackageName` is loaded into a `.qmd` file that is
being run with `engine: julia` the extension code in the `extension.jl` file
will be loaded. Below are the available interfaces that are can be extended.

#### `expand`

The `expand` function is used to inform `QuartoNotebookWorker` that a specific
Julia type should not be rendered and instead should be converted into a series
of notebook cells that are themselves evaluated and rendered. This allows for
notebooks to generate a dynamic number of cells based on runtime information
computed within the notebook rather than just the static cells of the original
notebook source.

The below example shows how to create a `Replicate` type that will be expanded
into `n` cells of the same value.

```julia
import PackageName
import QuartoNotebookWorker

function QuartoNotebookWorker.expand(r::PackageName.Replicate)
    # Return a list of notebook `Cell`s to be rendered.
    return [QuartoNotebookWorker.Cell(r.value) for _ in 1:r.n]
end
```

Where `PackageName` itself defines the `Replicate` type as

```julia
module PackageName

export Replicate

struct Replicate
    value
    n::Int
end

end
```

The `Cell` type takes a value, which can be any Julia type. If it is a
`Function` then the result of the `Cell` will be the result of calling the
`value()`, including any printing to `stdout` and `stderr` that may occur during
the call. If it is any other type then the result of the `Cell` will be the
value itself.

> [!NOTE]
>
> To return a `Function` itself as the output of the `Cell` you can wrap it
> with `Returns(func)`, which will then not call `func`.

Optional `code` keyword allows fake source code for the cell to be set, which
will be rendered by `quarto`. Note that the source code is never parsed or
evaluated. Additionally the `options` keyword allows for defining cell options
that will be passed to `quarto` to control cell rendering such as captions,
layout, etc.

Within a `.qmd` file you can then use the `Replicate` type as follows:

````qmd
```{julia}
using PackageName
```

Generate two cells that each output `"Hello"` as their returned value.

```{julia}
Replicate("Hello", 2)
```

Next we generate three cells that each push the current `DateTime` to a shared
`state` vector, print `"World"` to `stdout` and then return the entire `state`
for rendering. The `echo: false` option is used to suppress the output of the
original cell itself.

```{julia}
#| echo: false
import Dates
let state = []
    Replicate(3) do
        push!(state, Dates.now())
        println("World")
        return state
    end
end
```
````
