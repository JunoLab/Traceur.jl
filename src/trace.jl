struct Trace
  seen::Set
  warn
end

Trace(w) = Trace(Set(), w)

isprimitive(f) = f isa Core.Builtin || f isa Core.IntrinsicFunction

const ignored_methods = [@which((1,2)[1])]

@primitive ctx::Trace function (f::Any)(args...)
  C, T = Call(f, args...), typeof.((f, args...))
  (T ∈ ctx.seen || isprimitive(f) ||
    method(C) ∈ ignored_methods) && return f(args...)
  push!(ctx.seen, T)
  result = overdub(ctx, f, args...)
  analyse((a...) -> ctx.warn(Warning(a...)), C)
  return result
end

trace(w, f) = overdub(Trace(w), f)

function warntrace(f)
  call = nothing
  function warn(w)
    if (w.f, w.a) != call
      call = (w.f, w.a)
      method = which(w.f, w.a)
      print_with_color(:yellow, method_expr(call...),
                       " at $(method.file):$(method.line)", '\n')
    end
    println("  ", w.message, w.line != -1 ? " at line $(w.line)" : "")
  end
  trace(warn, f)
end

function warnings(f)
  warnings = Warning[]
  trace(w -> push!(warnings, w), f)
  return warnings
end

macro trace(ex)
  :(warntrace(() -> $(esc(ex))))
end
