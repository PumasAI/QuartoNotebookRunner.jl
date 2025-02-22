# `Revise` integration for `quarto preview`

This environment allows for running `QuartoNotebookRunner` with `Revise`
enabled. That means that you can edit code within the `QuartoNotebookRunner`
module that a `quarto` process is using for `engine: julia` notebooks and have
those changes take effect on the next render request that is triggered by a
notebook file change. Without this feature you need to manually close and
restart the `julia` process on each change.

## Usage

A `justfile` is provided that will start a `quarto` server with `Revise` enabled.

```
$ just revise quarto preview filename.qmd
```

If you terminate the command and need to force close any leftover `julia` server
processes then run:

```
$ just close
```

## `QuartoNotebookWorker` code revision

To enable `Revise` for the `QuartoNotebookWorker` module, you must have
`Revise` installed as a dependency in the notebook environment, it cannot be a
global environment dependency since this is not part of the `LOAD_PATH` for
notebooks. Then set the `QUARTO_ENABLE_REVISE=true` environment variable for
your notebook in the `julia.env` frontmatter key.
