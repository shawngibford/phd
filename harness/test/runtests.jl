"""
runtests.jl — PHD harness test suite (stdlib `Test`, no third-party deps)

    julia harness/test/runtests.jl

Turns the manual gates used during development into a permanent, CI-runnable suite.
Covers the pure logic (metric/aggregation/Welch, JSON round-trip, id/seed helpers,
ledger-row formatting) and a fixture-based group reap (no real detached runner).
"""

using Test

const HARNESS = abspath(joinpath(@__DIR__, ".."))

@testset "PHD harness" begin
    include(joinpath(@__DIR__, "test_metric.jl"))
    include(joinpath(@__DIR__, "test_jobctl.jl"))
    include(joinpath(@__DIR__, "test_poller.jl"))
end
