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

function code(c::Call; optimize = false)
  codeinfo = code_typed(c.f, argtypes(c), optimize = optimize)
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

exprtype(code, x) = typeof(x)
exprtype(code, x::Expr) = x.typ
exprtype(code, x::QuoteNode) = typeof(x.value)
exprtype(code, x::SSAValue) = code.ssavaluetypes[x.id+1]
exprtype(code, x::SlotNumber) = code.slottypes[x.id]

function assignments(code, l = -1)
  assigns = Dict()
  eachline(code, l) do line, ex
    (isexpr(ex, :(=)) && isexpr(ex.args[1], SlotNumber)) || return
    typ = exprtype(code, ex.args[2])
    push!(get!(assigns, ex.args[1], []), (line, typ))
  end
  return assigns
end

function locals(warn, call)
  l = method(call).line
  c = code(call)[1]
  as = assignments(c, l)
  for (x, as) in as
    (length(unique(map(x->x[2],as))) == 1 && isleaftype(as[1][2])) && continue
    var = c.slotnames[x.id]
    for (l, t) in as
      warn(call, l, "$var is assigned as $t")
    end
  end
end

# global variables

function globals(warn, call)
  c = code(call)[1]
  eachline(c) do line, ex
    (isexpr(ex, :(=)) && isexpr(ex.args[2], GlobalRef)) || return
    ref = ex.args[2]
    isconst(ref.mod, ref.name) ||
      warn(call, line, "uses global variable $(ref.mod).$(ref.name)")
  end
end

# dynamic dispatch

rebuild(code, x) = x
rebuild(code, x::Expr) = Expr(x.head, rebuild.(code, x.args)...)
rebuild(code, x::SlotNumber) = code.slotnames[x.id]

function rebuild(code, x::SSAValue)
  for ex in code.code
    isexpr(ex, :(=)) && ex.args[1] == x && return rebuild(code, ex.args[2])
  end
  error("$x not found")
end

function dispatch(warn, call)
  c = code(call, optimize = true)[1]
  eachline(c, method(call).line) do line, ex
    (isexpr(ex, :(=)) && isexpr(ex.args[2], :call)) || return
    callex = rebuild(c, ex.args[2])
    f = callex.args[1]
    f isa GlobalRef && isprimitive(getfield(f.mod, f.name)) && return
    warn(call, line, "dynamic dispatch to $(callex)")
  end
end

# return type

function rettype(warn, call)
  c, out = code(call)
  isleaftype(out) || warn(call, "returns $out")
end

# overall analysis

function analyse(warn, call)
  globals(warn, call)
  locals(warn, call)
  dispatch(warn, call)
  rettype(warn, call)
end
