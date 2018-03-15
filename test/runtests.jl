using Traceur
using Traceur: warnings
using Base.Test

warns_for(ws, x) = any(w -> contains(w.message, x), ws)
warns_for(ws, x, xs...) = warns_for(ws, x) && warns_for(ws, xs...)

y = 1

@testset "Traceur" begin

naive_relu(x) = x < 0 ? 0 : x

ws = warnings(() -> naive_relu(1))
@test isempty(ws)

ws = warnings(() -> naive_relu(1.0))
@test warns_for(ws, "returns")

function naive_sum(xs)
  s = 0
  for x in xs
    s += x
  end
  return s
end

ws = warnings(() -> naive_sum(1))
@test isempty(ws)

ws = warnings(() -> naive_sum(1.0))
@test warns_for(ws, "assigned", "dispatch", "returns")

f(x) = x+y

ws = warnings(() -> f(1))
@test warns_for(ws, "global", "dispatch", "returns")

@test_nowarn @trace naive_sum(1.0)

@test_nowarn @trace_static naive_sum(1.0)

end
