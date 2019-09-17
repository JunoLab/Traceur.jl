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

function f2(x)
  foo = y
  sin(x)+y
end

g(x) = x+cy

naive_sum_wrapper(x) = naive_sum(x)

x = 1
my_add(y) = x + y

module Foo
module Bar
function naive_sum(xs)
  s = 0
  for x in xs
    s += x
  end
  return s
end
end
naive_sum_wrapper(x) = Bar.naive_sum(x)
end

@should_not_warn my_stable_add(y) = my_add(y)
my_stable_add_undecorated(y) = my_add(y)

@testset "Traceur" begin
  ws = Traceur.warnings(() -> naive_relu(1))
  @test isempty(ws)

  ws = Traceur.warnings(() -> naive_relu(1.0))
  @test warns_for(ws, "returns")

  ws = Traceur.warnings(() -> randone())
  @test warns_for(ws, "returns")

  ws = Traceur.warnings(() -> naive_sum([1]))
  if Base.VERSION >= v"1.2.0"
    @test length(ws) == 4
    @test warns_for(ws, "assigned")
  else
    @test isempty(ws)
  end

  ws = Traceur.warnings(() -> naive_sum([1.0]))
  @test warns_for(ws, "assigned", "returns")

  ws = Traceur.warnings(() -> f(1))
  @test warns_for(ws, "global", "dispatch", "returns")

  ws = Traceur.warnings(() -> f2(1))
  @test warns_for(ws, "global", "dispatch", "returns")

  ws = Traceur.warnings(() -> g(1))
  @test isempty(ws)

  @testset "depth limiting" begin
    ws = Traceur.warnings(() -> naive_sum_wrapper(rand(3)); maxdepth = 0)
    @test length(ws) == 1
    @test warns_for(ws, "returns")

    ws = Traceur.warnings(() -> naive_sum_wrapper(rand(3)); maxdepth = 1)
    if Base.VERSION >= v"1.2.0"
      @test length(ws) == 6
    else
      @test length(ws) == 4
    end
    @test warns_for(ws, "assigned", "returns")
  end

  @testset "module specific" begin
    ws = Traceur.warnings(() -> Foo.naive_sum_wrapper(rand(3)); maxdepth = 2, modules=[Foo])
    @test length(ws) == 1
    @test warns_for(ws, "returns")

    ws = Traceur.warnings(() -> Foo.naive_sum_wrapper(rand(3)); maxdepth = 2, modules=[Foo.Bar])
    if Base.VERSION >= v"1.2.0"
      @test length(ws) == 5
    else
      @test length(ws) == 3
    end
    @test warns_for(ws, "assigned", "returns")

    ws = Traceur.warnings(() -> Foo.naive_sum_wrapper(rand(3)); maxdepth = 2, modules=[Foo, Foo.Bar])
    if Base.VERSION >= v"1.2.0"
      @test length(ws) == 6
    else
      @test length(ws) == 4
    end
    @test warns_for(ws, "assigned", "returns")
  end

  @testset "test utilities" begin
    @test_nowarn @check my_add(1)
    @test_throws AssertionError @check my_stable_add(1)
    @test_throws AssertionError @check my_stable_add_undecorated(1) nowarn=[my_stable_add_undecorated]
    @test_throws AssertionError @check my_stable_add_undecorated(1) nowarn=:all
    function bar(x)
      x > 0 ? 1.0 : 1
    end
    @test_nowarn @check(bar(2)) == 1.0
    @test_nowarn @check(bar(2), maxdepth=100) == 1.0
    @test_nowarn @check(bar(2), nowarn=[]) == 1.0
    @test_nowarn @check(bar(2), nowarn=[], maxdepth=100) == 1.0
    @test_nowarn @check(bar(2), nowarn=Any[]) == 1.0
    @test_nowarn @check(bar(2), nowarn=Any[], maxdepth=100) == 1.0
    @test_throws AssertionError @check(bar(2), nowarn=[bar])
    @test_throws AssertionError @check(bar(2), nowarn=[bar], maxdepth=100)
    @test_throws AssertionError @check(bar(2), nowarn=Any[bar])
    @test_throws AssertionError @check(bar(2), nowarn=Any[bar], maxdepth=100)
    @test_throws AssertionError @check(bar(2), nowarn=:all)
    @test_throws AssertionError @check(bar(2), nowarn=:all, maxdepth=100)
    @test_nowarn @check(bar(2), except=[bar]) == 1.0
    @test_nowarn @check(bar(2), except=[bar], maxdepth=100) == 1.0
    @test_nowarn @check(bar(2), except=Any[bar]) == 1.0
    @test_nowarn @check(bar(2), except=Any[bar], maxdepth=100) == 1.0
  end
end
