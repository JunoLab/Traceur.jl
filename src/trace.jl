struct Trace
  seen::Set
end

Trace() = Trace(Set())

isprimitive(f) = f isa Core.Builtin || f isa Core.IntrinsicFunction

const ignored_methods = [@which((1,2)[1])]

@primitive ctx::Trace function (f::Any)(args...)
  T = typeof.((f, args...))
  (T ∈ ctx.seen || isprimitive(f) ||
    method(f, args...) ∈ ignored_methods) && return f(args...)
  push!(ctx.seen, T)
  result = overdub(ctx, f, args...)
  analyse(f, args...)
  return result
end

macro trace(ex)
  :(@overdub Trace() $(esc(ex)))
end
