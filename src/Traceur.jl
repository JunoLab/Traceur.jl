module Traceur

using MacroTools
using Vinyl: @primitive, overdub
using ASTInterpreter2: linearize!

import Core.MethodInstance

export @trace

include("analysis.jl")
include("trace.jl")

end # module
