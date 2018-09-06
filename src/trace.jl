using Cassette, InteractiveUtils

Cassette.@context TraceurCtx

struct Trace
  seen::Set
  warn
end

Trace(w) = Trace(Set(), w)

isprimitive(f) = f isa Core.Builtin || f isa Core.IntrinsicFunction

const ignored_methods = [@which((1,2)[1])]

function Cassette.posthook(ctx::TraceurCtx, out, f, args...)
  C, T = DynamicCall(f, args...), typeof.((f, args))
  tra = ctx.metadata
  (T ∈ tra.seen || isprimitive(f) || method(C) ∈ ignored_methods ||
    method(C).module ∈ (Core, Core.Compiler)) && return nothing

  analyse((a...) -> tra.warn(Warning(a...)), C)
  return nothing
end

trace(w, f) = Cassette.overdub(TraceurCtx(metadata=Trace(w)), f)

warntrace(f) = trace(warning_printer(), f)

function warnings(f)
  warnings = Warning[]
  trace(w -> push!(warnings, w), f)
  return warnings
end

macro trace(ex)
  :(warntrace(() -> $(esc(ex))))
end
