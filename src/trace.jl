using Cassette, InteractiveUtils

Cassette.@context TraceurCtx

struct Trace
  seen::Set
  stack::Vector{Call}
  warn
end

Trace(w) = Trace(Set(), Vector{Call}(), w)

isprimitive(f) = f isa Core.Builtin || f isa Core.IntrinsicFunction

const ignored_methods = Set([@which((1,2)[1])])
const ignored_functions = Set([getproperty, setproperty!])

function Cassette.prehook(ctx::TraceurCtx, f, args...)
  tra = ctx.metadata
  C = DynamicCall(f, args...)
  push!(tra.stack, C)
  nothing
end

function Cassette.posthook(ctx::TraceurCtx, out, f, args...)
  tra = ctx.metadata
  C = tra.stack[end]
  T = typeof.((f, args))
  if !(f ∈ ignored_functions || T ∈ tra.seen || isprimitive(f) ||
       method(C) ∈ ignored_methods || method(C).module ∈ (Core, Core.Compiler))
    push!(tra.seen, T)
    analyse((a...) -> tra.warn(Warning(a..., copy(tra.stack))), C)
  end
  pop!(tra.stack)
  nothing
end

trace(w, f) = Cassette.recurse(TraceurCtx(metadata=Trace(w)), f)

warntrace(f) = trace(warning_printer(), f)

function warnings(f)
  warnings = Warning[]
  trace(w -> push!(warnings, w), f)
  return warnings
end

macro trace(ex)
  :(warntrace(() -> $(esc(ex))))
end
