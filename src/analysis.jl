abstract type Call end

method_expr(f, Ts::Type{<:Tuple}) =
  :($f($([:(::$T) for T in Ts.parameters]...)))

function loc(c::Call)
  meth = method(c)
  "$(meth.file):$(meth.line)"
end

struct DynamicCall{F,A} <: Call
  f::F
  a::A
  DynamicCall{F,A}(f,a...) where {F,A} = new(f, a)
end

DynamicCall(f, a...) = DynamicCall{typeof(f),typeof(a)}(f, a...)

argtypes(c::DynamicCall) = Base.typesof(c.a...)
types(c::DynamicCall) = (typeof(c.f), argtypes(c).parameters...)
method(c::DynamicCall) = which(c.f, argtypes(c))
method_expr(c::DynamicCall) = method_expr(f, argtypes(c))

function code(c::DynamicCall; optimize = false)
  codeinfo = code_typed(c.f, argtypes(c), optimize = optimize)
  @assert length(codeinfo) == 1
  codeinfo = codeinfo[1]
  linearize!(codeinfo[1])
  return codeinfo
end

struct StaticCall <: Call
  method_instance::MethodInstance
end

argtypes(c::StaticCall) = Tuple{c.method_instance.specTypes.parameters[2:end]...}
types(c::StaticCall) = c.method_instance.specTypes
method(c::StaticCall) = c.method_instance.def

function method_expr(c::StaticCall)
  name = GlobalRef(method(c).module, method(c).name)
  args = join(["::$typ" for typ in argtypes(c)], ", ")
  # TODO can't return a nice expr for types without args. string will do for now
  "$name($args)"
end

function code(c::StaticCall; optimize = false)
  # TODO static call graph can only be computed with optimize=true, so analyzing with optimized=false will skip inlined methods
  codeinfo = get_code_info(c.method_instance, optimize=true)
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

exprtype(code, x) = typeof(x)
exprtype(code, x::Expr) = x.typ
exprtype(code, x::QuoteNode) = typeof(x.value)
exprtype(code, x::SSAValue) = code.ssavaluetypes[x.id+1]
exprtype(code, x::SlotNumber) = code.slottypes[x.id]

rebuild(code, x) = x
rebuild(code, x::QuoteNode) = x.value
rebuild(code, x::Expr) = Expr(x.head, rebuild.(code, x.args)...)
rebuild(code, x::SlotNumber) = code.slotnames[x.id]

struct Warning
  f
  a::Type{<:Tuple}
  line::Int
  message::String
end

Warning(c::Call, line, message) = Warning(c.f, argtypes(c), line, message)
Warning(meth, message) = Warning(meth, -1, message)

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

# fields

function fields(warn, call)
  c = code(call)[1]
  eachline(c) do line, x
    (isexpr(x, :(=)) && isexpr(x.args[2], :call) &&
     rebuild(c, x.args[2].args[1]) == GlobalRef(Core,:getfield)) ||
      return
    x, field = x.args[2].args[2:3]
    x, x_expr, field = exprtype(c, x), rebuild(c, x), rebuild(c, field)
    (isleaftype(x) && !(x.name.wrapper == Type) && field isa Symbol) ||
      return
    isleaftype(fieldtype(x, field)) || warn(call, line, "field $x_expr.$field::$(fieldtype(x, field)), $x_expr::$x")
  end
end

# local variables

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

# dynamic dispatch

function rebuild(code, x::SSAValue)
  for ex in code.code
    isexpr(ex, :(=)) && ex.args[1] == x && return rebuild(code, ex.args[2])
  end
  error("$x not found")
end

function dispatch(warn, call)
  c = code(call, optimize = true)[1]
  eachline(c, method(call).line) do line, ex
    isexpr(ex, :(=)) && (ex = ex.args[2])
    isexpr(ex, :call) || return
    callex = rebuild(c, ex)
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
  fields(warn, call)
  locals(warn, call)
  dispatch(warn, call)
  rettype(warn, call)
end
