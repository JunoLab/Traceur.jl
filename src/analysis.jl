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
method_expr(c::DynamicCall) = method_expr(c.f, argtypes(c))

function code(c::DynamicCall; optimize = false)
  codeinfo = code_typed(c.f, argtypes(c), optimize = optimize)
  @assert length(codeinfo) == 1
  codeinfo = codeinfo[1]
  return codeinfo
end

# struct StaticCall <: Call
#   method_instance::MethodInstance
# end
#
# argtypes(c::StaticCall) = Tuple{c.method_instance.specTypes.parameters[2:end]...}
# types(c::StaticCall) = c.method_instance.specTypes
# method(c::StaticCall) = c.method_instance.def
#
# method_expr(c::StaticCall) = method_expr(method(c).name, argtypes(c))
#
# function code(c::StaticCall; optimize = false)
#   # TODO static call graph can only be computed with optimize=true, so analyzing with optimized=false will skip inlined methods
#   codeinfo = get_code_info(c.method_instance, optimize=true)
#   linearize!(codeinfo[1])
#   return codeinfo
# end

function eachline(f, code, line = -1)
  for (i, l) in enumerate(code.code)
    ind = code.codelocs[i]
    1 <= ind <=  length(code.linetable) ?
      line = code.linetable[ind].line :
      line = -1
    f(line, l)
  end
end

exprtype(code, x) = typeof(x)
exprtype(code, x::Core.TypedSlot) = x.typ
exprtype(code, x::QuoteNode) = typeof(x.value)
exprtype(code, x::Core.SSAValue) = code.ssavaluetypes[x.id+1]
# exprtype(code, x::Core.SlotNumber) = code.slottypes[x.id]

rebuild(code, x) = x
rebuild(code, x::QuoteNode) = x.value
rebuild(code, x::Expr) = Expr(x.head, rebuild.(Ref(code), x.args)...)
rebuild(code, x::Core.SlotNumber) = code.slotnames[x.id]

struct Warning
  call::Call
  line::Int
  message::String
end

Warning(call, message) = Warning(call, -1, message)

function warning_printer()
  (w) -> begin
    meth = method(w.call)
    # TODO: figure out file of call, and then print `method_expr(call)`
    @safe_warn w.message _file=String(meth.file) _line=w.line _module=nothing
  end
end

# global variables

function globals(warn, call)
  c = code(call)[1]
  eachline(c) do line, ex
    ex isa Expr || return
    for ref in ex.args
      ref isa GlobalRef || continue
      isconst(ref.mod, ref.name) && continue
      warn(call, line, "uses global variable $(ref.mod).$(ref.name)")
    end
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
    (isconcretetype(x) && !(x.name.wrapper == Type) && field isa Symbol) ||
      return
    isconcretetype(fieldtype(x, field)) || warn(call, line, "field $x_expr.$field::$(fieldtype(x, field)), $x_expr::$x")
  end
end

# local variables

function assignments(code, l = -1)
  assigns = Dict()
  idx = 0
  eachline(code, l) do line, ex
    idx += 1
    (isexpr(ex, :(=)) && isexpr(ex.args[1], Core.SlotNumber)) || return
    typ = Core.Compiler.widenconst(code.ssavaluetypes[idx])
    push!(get!(assigns, ex.args[1], []), (line, typ))
  end
  return assigns
end

function locals(warn, call)
  c = code(call)[1]
  as = assignments(c)
  for (x, as) in as
    (length(unique(map(x->x[2],as))) == 1 && (isconcretetype(as[1][2]) || istype(as[1][2]))) && continue
    var = c.slotnames[x.id]
    startswith(string(var), '#') && continue
    for (l, t) in as
      warn(call, l, "$var is assigned as $t")
    end
  end
end

# dynamic dispatch

rebuild(code, x::Core.SSAValue) = rebuild(code, code.code[x.id])

function dispatch(warn, call)
  c = code(call, optimize = true)[1]
  eachline(c) do line, ex
    isexpr(ex, :(=)) && (ex = ex.args[2])
    isexpr(ex, :call) || return
    callex = rebuild(c, ex)
    f = callex.args[1]
    (f isa GlobalRef && isprimitive(getfield(f.mod, f.name)) || isprimitive(f)) && return
    warn(call, line, string("dynamic dispatch to ", callex))
  end
end

# return type

function issmallunion(t)
  ts = Base.uniontypes(t)
  length(ts) == 1 && isconcretetype(first(ts)) && return true
  length(ts) > 2 && return false
  (Missing in ts || Nothing in ts) && return true
  return false
end

istype(::Type{T}) where T = true
istype(::Union) = false
istype(x) = false

function rettype(warn, call)
  c, out = code(call)

  if out == Any || !(issmallunion(out) || isconcretetype(out) || istype(out))
    warn(call, method(call).line, "$(call.f) returns $out")
  end
end

# overall analysis

function analyse(warn, call)
  globals(warn, call)
  locals(warn, call)
  fields(warn, call)
  dispatch(warn, call)
  rettype(warn, call)
end
