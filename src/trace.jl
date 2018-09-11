using Cassette, InteractiveUtils

Cassette.@context TraceurCtx

struct Trace
  seen::Set
  warn
end

Trace(w) = Trace(Set(), w)

isprimitive(f) = f isa Core.Builtin || f isa Core.IntrinsicFunction

const ignored_methods = Set([@which((1,2)[1])])
const ignored_functions = Set([getproperty, setproperty!])

function Cassette.posthook(ctx::TraceurCtx, out, f, args...)
  C, T = DynamicCall(f, args...), typeof.((f, args))
  tra = ctx.metadata
  (f ∈ ignored_functions || T ∈ tra.seen || isprimitive(f) ||
    method(C) ∈ ignored_methods || method(C).module ∈ (Core, Core.Compiler)) && return nothing

  push!(tra.seen, T)
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
