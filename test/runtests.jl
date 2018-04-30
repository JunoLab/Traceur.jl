using Traceur
using Base.Test

warns_for(ws, x) = any(w -> contains(w.message, x), ws)
warns_for(ws, x, xs...) = warns_for(ws, x) && warns_for(ws, xs...)

y = 1

naive_relu(x) = x < 0 ? 0 : x

function naive_sum(xs)
  s = 0
  for x in xs
    s += x
  end
  return s
end

f(x) = x+y

function test(warnings)
  ws = warnings(() -> naive_relu(1))
  @test isempty(ws)

  ws = warnings(() -> naive_relu(1.0))
  @test warns_for(ws, "returns")

  ws = warnings(() -> naive_sum(1))
  @test isempty(ws)

  ws = warnings(() -> naive_sum(1.0))
  @test warns_for(ws, "assigned", "dispatch", "returns")

  ws = warnings(() -> f(1))
  @test warns_for(ws, "global", "dispatch", "returns")
end

@testset "Traceur" begin
  @testset "Dynamic" begin
    test(Traceur.warnings)
  end
  @testset "Static" begin
    test(Traceur.warnings_static)
  end
  @test_nowarn @trace naive_sum(1.0)
  @test_nowarn @trace_static naive_sum(1.0)
end


end
