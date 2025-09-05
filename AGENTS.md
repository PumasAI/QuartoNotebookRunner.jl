# AGENTS.md

Guidance for AI coding assistants working with QuartoNotebookRunner.jl.

## Architecture

QuartoNotebookRunner.jl serves as the Julia evaluation engine for Quarto's `engine: julia` directive.

### Main Package (`src/`)
- Manages notebook parsing and worker process orchestration
- `server.jl`: Core server managing notebook execution
- `socket.jl`: JSON API for Quarto CLI communication
- `worker.jl`: Worker process lifecycle management
- `Malt.jl`: Custom vendored process management

### Worker Package (`src/QuartoNotebookWorker/`)
- Runs in isolated Julia processes for notebook execution
- All dependencies vendored in `vendor/` to avoid conflicts
- `NotebookState.jl`: Manages execution state and module isolation
- `render.jl`: Handles output rendering and MIME types
- Extensions in `ext/` use Julia's lazy-loading mechanism via `register_package_hooks`

## Development Guidelines

### Extension Hooks & Dynamic Cells

Extensions register lifecycle hooks: `add_package_loading_hook!`, `add_package_refresh_hook!`, `add_post_eval_hook!`, `add_post_error_hook!`.

The `expand` function enables runtime cell generation, bypassing Quarto's static limitations. Extensions implement `QuartoNotebookWorker.expand(obj)` to return `Cell` vectors for iterating over data, conditional generation, and programmatic notebook construction.

### Testing & Version Control

- **Tests**: Unit tests in `test/testsets/`, integration tests in `test/testsets/integrations/`
- **Before committing**: Run `just format` (see Commands section)
- **Commits**: Use conventional commit style `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `style`
  - Example: `feat(ext): add DataFrames integration`
- Always ask the user to run tests when needed

### Commands

```bash
just format    # format the entire codebase
just changelog # generate correct PR links for changelog entries
```

## Key Design Principles

- Each notebook runs in isolated Julia process with fresh module
- Worker processes reused between runs for performance
- Non-constant globals GC'd between runs to prevent memory leaks

## Environment Variables

- `QUARTO_JULIA`: Specify Julia binary path
- `QUARTONOTEBOOKRUNNER_EXEFLAGS`: Additional Julia flags for workers
- `QUARTO_ENABLE_REVISE`: Enable Revise in worker processes

## Socket Server Protocol

JSON API supports notebook execution, status queries, and worker management. See `test/testsets/socket_server/client.js` for implementation.

## Guidelines for AI Assistants

- Match surrounding code patterns
- Verify worker cleanup after debugging
- Use existing extensions as templates
- When updating this file: use positive wording, keep instructions concise and actionable