const should_not_warn = Set{Function}()

"""
    @should_not_warn function foo(x)
      ...
    end

Add `foo` to the list of functions in which no warnings may occur (checkd by `@check`).
"""
macro should_not_warn(expr)
  quote
    fun = $(esc(expr))
    push!(should_not_warn, fun)
    fun
  end
end

"""
    check(f::Function; nowarn=[], kwargs...)

Run Traceur on `f`, and throw an error if any warnings occur inside functions
tagged with `@should_not_warn` or specified in `nowarn`. To throw an error
if any warnings occur inside any functions, set `nowarn=:all`.
"""
function check(f; nowarn=Any[], kwargs...)
  if nowarn isa Symbol
    _nowarn = Any[]
    _nowarn_all = nowarn == :all
  else
    _nowarn = nowarn
    _nowarn_all = false
  end
  failed = false
  wp = warning_printer()
  result = trace(f; kwargs...) do warning
    ix = findfirst(warning.stack) do call
      _nowarn_all || call.f in should_not_warn || call.f in _nowarn
    end
    if ix != nothing
      tagged_function = warning.stack[ix].f
      message = "$(warning.message) (called from $(tagged_function))"
      warning = Warning(warning.call, warning.line, message, warning.stack)
      wp(warning)
      failed = true
    end
  end
  @assert !failed "One or more warnings occured inside functions tagged with `@should_not_warn` or specified with `nowarn`"
  result
end

"""
    @check fun(args...) nowarn=[] maxdepth=typemax(Int)

Run Traceur on `fun`, and throw an error if any warnings occur inside functions
tagged with `@should_not_warn` or specified in `nowarn`. To throw an error
if any warnings occur inside any functions, set `nowarn=:all`.
"""
macro check(expr, args...)
  quote
      check(() -> $(esc(expr)); $(map(esc, args)...))
    end
end
