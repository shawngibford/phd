using Test

include(joinpath(HARNESS, "metric.jl"))
using .MetricContract

@testset "metric.jl" begin
    @testset "rel_l2" begin
        @test rel_l2([1.0, 2.0], [1.0, 2.0]) == 0.0
        @test rel_l2([0.0, 0.0], [3.0, 4.0]) == 1.0          # ‖û−u‖/‖u‖ = 5/5
        @test isinf(rel_l2([1.0], [0.0]))                    # degenerate reference
    end

    @testset "aggregate" begin
        a = aggregate([0.03, 0.031, 0.029])
        @test a.n == 3 && isapprox(a.mean, 0.03, atol=1e-9) && a.std > 0
        @test aggregate(Float64[]).n == 0
        @test aggregate([0.04]).std == 0.0                   # single sample, no spread
        b = aggregate([0.05, Inf, NaN, 0.05])                # drop Inf/NaN
        @test b.n == 2 && isapprox(b.mean, 0.05)
    end

    @testset "quantum_advantage" begin
        adv = quantum_advantage(1.0, 2.0)
        @test adv.ratio == 0.5 && adv.meta["advantage_demonstrated"] == true
        none = quantum_advantage(1.0, nothing)
        @test isnan(none.ratio) && none.meta["no_baseline"] == true
        @test quantum_advantage(1.0, 0.0).meta["no_baseline"] == true   # zero baseline
    end

    @testset "welch_t (reference values)" begin
        # Two-sided p for t=2.0, df=10 ≈ 0.0734 (textbook).
        p = MetricContract._betai(10/2, 0.5, 10/(10 + 2.0^2))
        @test isapprox(p, 0.0734, atol=0.002)
        # log-gamma sanity
        @test isapprox(MetricContract._lgamma(5.0), log(24), atol=1e-6)
        @test isapprox(MetricContract._lgamma(0.5), 0.5*log(pi), atol=1e-6)
        # clear separation → tiny p
        w = welch_t(0.029, 0.003, 5, 0.041, 0.004, 5)
        @test w.p < 0.01 && w.df > 5 && w.df < 9
        # n<2 → undefined
        @test isnan(welch_t(0.1, 0.0, 1, 0.2, 0.01, 3).p)
    end

    @testset "is_improvement_agg (annotate-only)" begin
        # first result always keeps + significant
        d0 = is_improvement_agg(0.5, 0.0, 3, Inf, 0.0, 1)
        @test d0.keep && d0.significant
        # clear win → keep + significant (Welch p<0.05)
        d1 = is_improvement_agg(0.029, 0.003, 5, 0.041, 0.004, 5)
        @test d1.keep && d1.significant && d1.p < 0.05
        # mean improves but within noise → keep, NOT significant
        d2 = is_improvement_agg(0.0405, 0.01, 5, 0.041, 0.01, 5)
        @test d2.keep && !d2.significant
        # worse mean → no keep
        @test !is_improvement_agg(0.05, 0.001, 5, 0.04, 0.001, 5).keep
        # single-seed best (n<2) → fallback ~1σ, p = NaN
        d3 = is_improvement_agg(0.02, 0.001, 3, 0.03, 0.0, 1)
        @test d3.keep && isnan(d3.p)
    end
end
