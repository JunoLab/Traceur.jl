module Traceur

using MacroTools
# using Vinyl: @primitive, overdub
# using ASTInterpreter2: linearize!

import Core.MethodInstance

export @trace, @trace_static

include("analysis.jl")
include("trace.jl")
# include("trace_static.jl")

end # module
