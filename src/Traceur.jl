module Traceur

using MacroTools
# using Vinyl: @primitive, overdub
# using ASTInterpreter2: linearize!

import Core.MethodInstance

export @trace, @trace_static, @should_not_warn, @check

include("util.jl")
include("analysis.jl")
include("trace.jl")
# include("trace_static.jl")
include("check.jl")

end # module
