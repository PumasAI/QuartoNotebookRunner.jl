"""
    notebook_options() -> Dict{String,Any}

All Quarto options that are either set by the user within their notebook
frontmatter, or implicitly set by Quarto itself at runtime. Note that this is a
copy of the options used internally and mutation will not affect any other parts
of notebook evaluation.
"""
notebook_options() = deepcopy(NotebookState.OPTIONS[])

"""
    cell_options() -> Dict{String,Any}

The options for the current cell being evaluated. This is a copy of the options
used internally and mutation will not affect any other parts of notebook
evaluation.
"""
cell_options() = deepcopy(NotebookState.CELL_OPTIONS[])
