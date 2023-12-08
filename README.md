# Traceur

> [!WARNING]  
> This package is not maintained anymore. Please use e.g. [JET.jl](https://github.com/aviatesk/JET.jl) instead.

---
[![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://JunoLab.github.io/Traceur.jl/latest)

Traceur is essentially a codified version of the [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/). You run your code, it tells you about any obvious performance traps.

```julia
julia> using Traceur

julia> naive_relu(x) = x < 0 ? 0 : x

julia> @trace naive_relu(1.0)
naive_relu(::Float64) at none:1
    returns Union{Float64, Int64}
1.0

julia> function naive_sum(xs)
         s = 0
         for x in xs
           s += x
         end
         return s
       end

julia> @trace naive_sum([1.])
Base.indexed_next(::Tuple{Int64,Bool}, ::Int64, ::Int64) at tuple.jl:54
    returns Tuple{Union{Bool, Int64},Int64}
naive_sum(::Array{Float64,1}) at none:2
    s is assigned as Int64 at line 2
    s is assigned as Float64 at line 4
    dynamic dispatch to s + x at line 4
    returns Union{Float64, Int64}
1.0

julia> y = 1

julia> f(x) = x+y

julia> @trace f(1)
f(::Int64) at none:1
    uses global variable Main.y
    dynamic dispatch to x + Main.y at line 1
    returns Any
2
```

### Mechanics

The heavily lifting is done by [`analyse`](https://github.com/MikeInnes/Traceur.jl/blob/a107a2d9646675441e4e7c8d5f3be14d8bae86ad/src/analysis.jl#L127), which takes a `Call` (essentially a `(f, args...)` tuple for each function called in the code). Most of the analysis steps work by retrieving the `code_typed` of the function, inspecting it for issues and emitting any warnings.

Suggestions for (or better, implementations of!) further analysis passes are welcome.
