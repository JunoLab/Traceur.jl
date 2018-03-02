struct Call{F,A}
  f::F
  a::A
  Call{F,A}(f,a...) where {F,A} = new(f, a)
end

Call(f, a...) = Call{typeof(f),typeof(a)}(f, a...)

argtypes(c::Call) = Base.typesof(c.a...)
types(c::Call) = (typeof(c.f), argtypes(c).parameters...)

method(c::Call) = which(c.f, argtypes(c))

method_expr(f, Ts::Type{<:Tuple}) =
  :($f($([:(::$T) for T in Ts.parameters]...)))

method_expr(c::Call) = method_expr(f, argtypes(c))

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

struct Warning
  f
  a::Type{<:Tuple}
  line::Int
  message::String
end

Warning(c::Call, line, message) = Warning(c.f, argtypes(c), line, message)
Warning(meth, message) = Warning(meth, -1, message)

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

function warnlocals(warn, call)
  l = method(call).line
  c = code(call)[1]
  as = assignments(c, l)
  for (x, as) in as
    length(unique(map(x->x[2],as))) == 1 && continue
    var = c.slotnames[x.id]
    for (l, t) in as
      warn(call, l, "$var is assigned as $t")
    end
  end
end

# overall analysis

function analyse(warn, call)
  c, out = code(call)
  warnlocals(warn, call)
  isleaftype(out) ||
    warn(call, "returns $out")
end
