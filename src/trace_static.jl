function get_method_instance(f, typs) ::MethodInstance
  world = ccall(:jl_get_world_counter, UInt, ())
  tt = typs isa Type ? Tuple{typeof(f), typs.parameters...} : Tuple{typeof(f), typs...}
  results = Base._methods_by_ftype(tt, -1, world)
  @assert length(results) == 1 "get_method_instance should return one method, instead returned $(length(results)) methods: $results"
  (_, _, meth) = results[1]
  # TODO not totally sure what jl_match_method is needed for - I think it's just extracting type parameters like `where {T}`
  (ti, env) = ccall(:jl_match_method, Any, (Any, Any), tt, meth.sig)::SimpleVector
  meth = Base.func_for_method_checked(meth, tt)
  linfo = ccall(:jl_specializations_get_linfo, Ref{MethodInstance}, (Any, Any, Any, UInt), meth, tt, env, world)
end

function get_code_info(method_instance::MethodInstance; optimize=true) ::Tuple{CodeInfo, Type}
  world = ccall(:jl_get_world_counter, UInt, ())
  # TODO inlining=false would make analysis easier to follow, but it seems to break specialization on function types
  params = Core.Inference.InferenceParams(world)
  optimize = true
  cache = false # not sure if cached copies use the same params
  (_, code_info, return_typ) = Core.Inference.typeinf_code(method_instance, optimize, cache, params)
  (code_info, return_typ)
end

"Does this look like error reporting code ie not worth looking inside?"
function is_error_path(expr)
  expr == :throw ||
  expr == :throw_boundserror ||
  expr == :error ||
  expr == :assert ||
  (expr isa QuoteNode && is_error_path(expr.value)) ||
  (expr isa Expr && expr.head == :(.) && is_error_path(expr.args[2])) ||
  (expr isa GlobalRef && is_error_path(expr.name)) ||
  (expr isa MethodInstance && is_error_path(expr.def.name))
end

"Is it pointless to look inside this expression?"
function should_ignore(expr::Expr)
  is_error_path(expr.head) ||
  (expr.head == :call && is_error_path(expr.args[1])) ||
  (expr.head == :invoke && is_error_path(expr.args[1]))
end

"Return all function calls in the method whose argument types can be determined statically"
function get_child_calls(method_instance::MethodInstance)
  code_info, return_typ = get_code_info(method_instance, optimize=true)
  calls = Set{MethodInstance}()

  function walk_expr(expr)
    if isa(expr, MethodInstance)
      push!(calls, expr)
    elseif isa(expr, Expr)
      if !should_ignore(expr)
        foreach(walk_expr, expr.args)
      end
    end
  end
  foreach(walk_expr, code_info.code)

  calls
end

"A node in the call graph"
struct CallNode
  call::MethodInstance
  parent_calls::Set{MethodInstance}
  child_calls::Set{MethodInstance}
end

"Return as much of the call graph of `method_instance` as can be determined statically"
function get_call_graph(method_instance::MethodInstance, max_calls=1000::Int64) ::Vector{CallNode}
  all = Dict{MethodInstance, CallNode}()
  ordered = Vector{MethodInstance}()
  unexplored = Set{Tuple{Union{Void, MethodInstance}, MethodInstance}}(((nothing, method_instance),))
  for _ in 1:max_calls
    if isempty(unexplored)
      return [all[call] for call in ordered]
    end
    (parent, call) = pop!(unexplored)
    child_calls= get_child_calls(call)
    parent_calls = parent == nothing ? Set() : Set((parent,))
    all[call] = CallNode(call, parent_calls, child_calls)
    push!(ordered, call)
    for child_call in child_calls
      if !haskey(all, child_call)
        push!(unexplored, (call, child_call))
      else
        push!(all[child_call].parent_calls, call)
      end
    end
  end
  error("get_call_graph reached $max_calls calls and gave up")
end

@generated function show_structure(x)
  quote
    @show x
    $([:(isdefined(x, $(Expr(:quote, fieldname))) ? (@show x.$fieldname) : nothing) for fieldname in fieldnames(x)]...)
    x
  end
end

function trace_static(filter::Function, warn::Function, f::Function, typs)
  for call_node in get_call_graph(get_method_instance(f, typs))
    if filter(call_node.call)
      analyse((a...) -> warn(Warning(a...)), StaticCall(call_node.call))
    end
  end
end

warntrace_static(filter::Function, f::Function, typs) = trace_static(filter, warning_printer(), f, typs)
warntrace_static(f::Function, typs) = warntrace_static((_) -> true, f, typs)

@eval begin
  macro trace_static(ex0)
    Base.gen_call_with_extracted_types($(Expr(:quote, :warntrace_static)), ex0)
  end

  macro trace_static(filter, ex0)
    expr = Base.gen_call_with_extracted_types($(Expr(:quote, :warntrace_static)), ex0)
    insert!(expr.args, 2, esc(filter))
    expr
  end
end

function warnings_static(f)
  warnings = Warning[]
  trace_static((_) -> true, w -> push!(warnings, w), f, ())
  return warnings
end
