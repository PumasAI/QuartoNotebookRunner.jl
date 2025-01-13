# Malt.jl

Malt is a multiprocessing package for Julia.
You can use Malt to create Julia processes, and to perform computations in those processes.
Unlike the standard library package [`Distributed.jl`](https://docs.julialang.org/en/v1/stdlib/Distributed/),
Malt is focused on process sandboxing, not distributed computing.

```@docs
Malt
```



## Malt workers

We call the Julia process that creates processes the **manager,**
and the created processes are called **workers.**
These workers communicate with the manager using the TCP protocol.

Workers are isolated from one another by default.
There's no way for two workers to communicate with one another,
unless you set up a communication mechanism between them explicitly.

Workers have separate memory, separate namespaces, and they can have separate project environments;
meaning they can load separate packages, or different versions of the same package.

Since workers are separate Julia processes, the number of workers you can create,
and whether worker execution is multi-threaded will depend on your operating system.

```@docs
Malt.Worker
```

### Special workers

There are two special worker types that can be used for backwards-compatibility or other projects. You can also make your own worker type by extending the `Malt.AbstractWorker` type.

```@docs
Malt.InProcessWorker
Malt.DistributedStdlibWorker
```


## Calling Functions

The easiest way to execute code in a worker is with the `remote_call*` functions.

Depending on the computation you want to perform, you might want to get the result
synchronously or asynchronously; you might want to store the result or throw it away.
The following table lists each function according to its scheduling and return value:


| Function                        | Scheduling | Return value    |
|:--------------------------------|:-----------|:----------------|
| [`Malt.remote_call_fetch`](@ref) | Blocking   | <value>         |
| [`Malt.remote_call_wait`](@ref)  | Blocking   | `nothing`       |
| [`Malt.remote_call`](@ref)       | Async      | `Task` that resolves to <value>         |
| [`Malt.remote_do`](@ref)        | Async      | `nothing`       |


```@docs
Malt.remote_call_fetch
Malt.remote_call_wait
Malt.remote_call
Malt.remote_do
```

## Evaluating expressions

In some cases, evaluating functions is not enough. For example, importing modules
alters the global state of the worker and can only be performed in the top level scope.
For situations like this, you can evaluate code using the `remote_eval*` functions.

Like the `remote_call*` functions, there's different a `remote_eval*` depending on the scheduling and return value.

| Function                        | Scheduling | Return value    |
|:--------------------------------|:-----------|:----------------|
| [`Malt.remote_eval_fetch`](@ref) | Blocking   | <value>         |
| [`Malt.remote_eval_wait`](@ref)  | Blocking   | `nothing`       |
| [`Malt.remote_eval`](@ref)       | Async      | `Task` that resolves to <value>         |

```@docs
Malt.remote_eval_fetch
Malt.remote_eval_wait
Malt.remote_eval
Malt.worker_channel
```

## Exceptions

If an exception occurs on the worker while calling a function or evaluating an expression, this exception is rethrown to the host. For example:

```julia-repl
julia> Malt.remote_call_fetch(m1, :(sqrt(-1)))
ERROR: Remote exception from Malt.Worker on port 9115:

DomainError with -1.0:
sqrt will only return a complex result if called with a complex argument. Try sqrt(Complex(x)).
Stacktrace:
 [1] throw_complex_domainerror(f::Symbol, x::Float64)
   @ Base.Math ./math.jl:33
 [2] sqrt
   @ ./math.jl:591 [inlined]
 ...
```

The thrown exception is of the type `Malt.RemoteException`, and contains two fields: `worker` and `message::String`. The original exception object (`DomainError` in the example above) is not availabale to the host.

!!! note
    
    When using the async scheduling functions (`remote_call`, `remote_eval`), calling `wait` or `fetch` on the returned (failed) `Task` will throw a `Base.TaskFailedException`, not a `Malt.RemoteException`.
    
    (The `Malt.RemoteException` is available with `task_failed_exception.task.exception`.)


## Signals and Termination

Once you're done computing with a worker, or if you find yourself in an unrecoverable situation
(like a worker executing a divergent function), you'll want to terminate the worker.

The ideal way to terminate a worker is to use the `stop` function,
this will send a message to the worker requesting a graceful shutdown.

Note that the worker process runs in the same process group as the manager,
so if you send a [signal](https://en.wikipedia.org/wiki/Signal_(IPC)) to a manager,
the worker will also get a signal.

```@docs
Malt.isrunning
Malt.stop
Base.kill(::Malt.Worker)
Malt.interrupt
Malt.TerminatedWorkerException
```

