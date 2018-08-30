using Traceur, Test

warns_for(ws, x) = any(w -> occursin(x, w.message), ws)
warns_for(ws, x, xs...) = warns_for(ws, x) && warns_for(ws, xs...)

y = 1
const cy = 2
naive_relu(x) = x < 0 ? 0 : x

randone() = rand() < 0.5 ? Int(1) : rand() < 0.5 ? Float64(1) : BigInt(1)

function naive_sum(xs)
  s = 0
  for x in xs
    s += x
  end
  return s
end

f(x) = x+y
g(x) = x+cy

function test(warnings)
  ws = warnings(() -> naive_relu(1))
  @test isempty(ws)

  # returns a small union, so we shouldn't warn for that
  ws = warnings(() -> naive_relu(1.0))
  @test isempty(ws)
  # @test warns_for(ws, "returns")

  ws = warnings(() -> randone())
  @test warns_for(ws, "returns")

  ws = warnings(() -> naive_sum(1))
  @test isempty(ws)

  # returns a small union, so we shouldn't warn for that
  # dispatch pass is broken
  ws = warnings(() -> naive_sum(1.0))
  @test warns_for(ws, "assigned", #="dispatch", "returns"=#)

  # returns a small union, so we shouldn't warn for that
  # dispatch pass is broken
  ws = warnings(() -> f(1))
  @test warns_for(ws, "global", #="dispatch", "returns"=#)

  ws = warnings(() -> g(1))
  @test isempty(ws)
end

@testset "Traceur" begin
  @testset "Dynamic" begin
    test(Traceur.warnings)
  end
  # @testset "Static" begin
  #   test(Traceur.warnings_static)
  # end
  # @test_nowarn @trace naive_sum(1.0)
  # @test_nowarn @trace_static naive_sum(1.0)
end
