struct Call{F,A}
  f::F
  a::A
  Call(f,a...) = new(f, a)
end

Call(f, a...) = Call{typeof(f),typeof(a)}(f, a...)

argtypes(c::Call) = Base.typesof(c.a...)

method(c::Call) = which(c.f, argtypes(c))

function method_expr(c::Call)
  :($(c.f)($([:(::$T) for T in argtypes(c).parameters]...)))
end

function loc(c::Call)
  meth = method(c)
  "$(meth.file):$(meth.line)"
end

function code(c::Call)
  codeinfo = code_typed(c.f, argtypes(c), optimize=false)
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

# @code_typed(sum([1,2,3]))[1] |> fieldnames

function assignments(code, l = -1)
  assigns = Dict()
  eachline(code, l) do line, ex
    (isexpr(ex, :(=)) && isexpr(ex.args[1], SlotNumber)) || return
    typ = exprtype(ex.args[2])
    push!(get!(assigns, ex.args[1], []), (line, typ))
  end
  return assigns
end

function warnlocals(call)
  l = method(call).line
  c = code(call)[1]
  as = assignments(c, l)
  warned = false
  for (x, as) in as
    length(unique(map(x->x[2],as))) == 1 && continue
    if !warned
      warn("$(method_expr(call)) at $(loc(call))")
      warned = true
    end
    var = c.slotnames[x.id]
    for (l, t) in as
      println("$var is assigned $t at line $l")
    end
  end
end

# overall analysis

function analyse(call)
  c, out = code(call)
  warnlocals(call)
  isleaftype(out) ||
    warn("$(method_expr(call))::$out at $(loc(call))")
end
