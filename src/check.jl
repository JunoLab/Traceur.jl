const should_not_warn = Set{Function}()

# this is only a macro to avoid parens around function definitions:
# @should_not_warn
# function foo(x)
#   ...
# end
macro should_not_warn(expr)
  quote
    fun = $(esc(expr))
    push!(should_not_warn, fun)
    fun
  end
end

"""
    check(f::Function)

Run Traceur on f, and throw an error if any warnings occur inside functions tagged with @should_not_warn.
"""
function check(f)
  failed = false
  wp = warning_printer()
  result = trace(f) do warning
    ix = findfirst((call) -> call.f in should_not_warn, warning.stack)
    if ix != nothing
      tagged_function = warning.stack[ix].f
      message = "$(warning.message) (called from $(tagged_function))"
      warning = Warning(warning.call, warning.line, message, warning.stack)
      wp(warning)
      failed = true
    end
  end
  @assert !failed "One or more warnings occured inside functions tagged with @should_not_warn"
  result
end

macro check(expr)
  :(check(() -> $(esc(expr))))
end
