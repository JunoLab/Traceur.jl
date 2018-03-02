import Base: typesof

# utils

method(f, args...) = which(f, typesof(args...))

function method_expr(f, args...)
  :($f($([:(::$T) for T in typesof(args...).parameters]...)))
end

function loc(f, args...)
  meth = method(f, args...)
  "$(meth.file):$(meth.line)"
end

function code(f, args...)
  codeinfo = code_typed(f, typesof(args...), optimize=false)
  @assert length(codeinfo) == 1
  codeinfo = codeinfo[1]
  linearize!(codeinfo[1])
  return codeinfo
end

function eachline(f, code, line = -1)
  for l in code.code
    if l isa LineNumberNode
      line = l.line
    else
      f(line, l)
    end
  end
end

# local variables

exprtype(x) = typeof(x)
exprtype(x::Expr) = x.typ
exprtype(x::QuoteNode) = typeof(x.value)

function assignments(code, l = -1)
  assigns = Dict()
  eachline(code, l) do line, ex
    (isexpr(ex, :(=)) && isexpr(ex.args[1], SlotNumber)) || return
    typ = exprtype(ex.args[2])
    push!(get!(assigns, ex.args[1], []), (line, typ))
  end
  return assigns
end

function warnlocals(f, args...)
  l = method(f, args...).line
  c = code(f, args...)[1]
  as = assignments(c, l)
  warned = false
  for (x, as) in as
    length(unique(map(x->x[2],as))) == 1 && continue
    if !warned
      warn("$(method_expr(f, args...)) at $(loc(f, args...))")
      warned = true
    end
    var = c.slotnames[x.id]
    for (l, t) in as
      println("$var is assigned $t at line $l")
    end
  end
end

# overall analysis

function analyse(f, args...)
  c, out = code(f, args...)
  warnlocals(f, args...)
  isleaftype(out) ||
    warn("$(method_expr(f, args...))::$out at $(loc(f, args...))")
end
