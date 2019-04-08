# StochasticPrograms.jl

*A modeling framework for stochastic programming problems*

## Summary

StochasticPrograms models recourse problems where an initial decision is taken, unknown parameters are observed, followed by recourse decisions to correct any inaccuracy in the initial decision. The underlying optimization problems are formulated in [JuMP.jl](https://github.com/JuliaOpt/JuMP.jl). In StochasticPrograms, model instantiation can be deferred until required. As a result, scenario data can be loaded/reloaded to create/rebuild the recourse model at a later stage, possibly on separate machines in a cluster. Another consequence of deferred model instantiation is that StochasticPrograms.jl can provide stochastic programming constructs, such as *expected value of perfect information* ([`EVPI`](@ref)) and *value of the stochastic solution* ([`VSS`](@ref)), to gain deeper insights about formulated recourse problems. A good introduction to recourse models, and to the stochastic programming constructs provided in this package, is given in [Introduction to Stochastic Programming](https://link.springer.com/book/10.1007%2F978-1-4614-0237-4). A stochastic program has a structure that can be exploited in solver algorithms. Therefore, StochasticPrograms provides a structured solver interface, implemented by [LShapedSolvers.jl](@ref) and [ProgressiveHedgingSolvers.jl](@ref). StochasticPrograms has parallel capabilities, implemented using the standard Julia library for distributed computing.

## Features

- Flexible problem definition
- Deferred model instantiation
- Scenario data injection
- Natively distributed
- Interface to structure-exploiting solver algorithms
- Efficient parallel implementations of classical algorithms

Consider [Quick start](@ref) for a tutorial explaining how to get started using StochasticPrograms.

Some examples of models written in StochasticPrograms can be found on the [Examples](@ref) page.

See the [Index](@ref main-index) for the complete list of documented functions and types.

## Manual Outline

```@contents
Pages = ["manual/quickstart.md", "manual/data.md", "manual/modeldef.md", "manual/distributed.md", "manual/structuredsolvers.md", "manual/examples.md"]
```

## Library Outline

```@contents
Pages = ["library/public.md", "library/solverinterface.md"]
```

### [Index](@id main-index)

```@index
Pages = ["library/public.md"]
Order   = [:type, :macro, :function]
```
