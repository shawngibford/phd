"""
metric.jl — Experiment metric contract (PHD harness)

This file is a pure library: no side effects, no file I/O, no global state.
Projects `include` it and either use the default scorers or implement their own
`evaluate` method for their model/data types.

Public API
----------
    struct ExperimentResult            # canonical result carrier
    evaluate(model, data; budget_s)    # contract entry point (lower score = better)
    rel_l2(û, u)                       # default SciML scorer: relative L2 error
    quantum_advantage(cost_q, cost_c)  # quantum ratio; NaN + flag if no baseline

Lower score is always better.  score ∈ [0, ∞); 0 = perfect.

Metric contract rules (from §5 / §5 candor rule)
-------------------------------------------------
  1. Lower is better.  Must be vocab/scale-independent and reproducible under
     a fixed seed.
  2. Quantum advantage: a classical baseline is REQUIRED in meta.  If absent,
     quantum_advantage() returns NaN and sets meta["no_baseline"] = true.
     The poller will record the result as "speculative, no advantage demonstrated."
  3. Projects extend evaluate() by adding methods for their model/data types.
     The default implementation (a toy quadratic) is only for self-testing.
"""

module MetricContract

using LinearAlgebra: norm
using Statistics: mean, std

export ExperimentResult, evaluate, rel_l2, quantum_advantage, aggregate, is_improvement_agg, welch_t

# ---------------------------------------------------------------------------
# Result carrier
# ---------------------------------------------------------------------------

"""
    ExperimentResult(score, wall_s, meta)

Canonical result returned by evaluate().

Fields
------
    score   :: Float64          Lower is better. Vocab/scale-independent.
    wall_s  :: Float64          Wall-clock time of the measurement (seconds).
    meta    :: Dict{String,Any} Free-form metadata: loss curves, baseline costs,
                                epoch count, backend, etc.  Written verbatim into
                                epoch/NNNN.json and result.json.

The `meta` dict SHOULD contain at least:
    "epochs"          => Int     — number of training epochs completed
    "final_loss"      => Float64 — raw training loss (for debugging)
    "backend"         => String  — backend used ("cpu", "metal", "cuda")

For quantum experiments, meta MUST also contain:
    "cost_q"                 => Float64  — quantum circuit cost
    "cost_classical_baseline"=> Float64  — fairly-tuned classical cost
    "quantum_advantage_ratio"=> Float64  — cost_q / cost_classical_baseline
"""
struct ExperimentResult
    score  :: Float64
    wall_s :: Float64
    meta   :: Dict{String,Any}
end

# ---------------------------------------------------------------------------
# Contract entry point
# ---------------------------------------------------------------------------

"""
    evaluate(model, data; budget_s::Float64) -> ExperimentResult

The single entry point the runner calls at the END of every epoch (and for the
final result).  Projects override this by adding methods for their own model and
data types.  The runner calls:

    result = evaluate(model, data; budget_s = remaining_budget_s)

If the evaluation itself runs out of time it should return what it has (partial
score is still valid).

Default method: toy quadratic baseline — used only when no project-specific
method is defined (e.g., for self-testing runner.jl without a real model).
"""
function evaluate(model, data; budget_s::Float64 = Inf)::ExperimentResult
    # Default: model is expected to be callable as model(x) -> ŷ
    # data is expected to be a NamedTuple with fields :x and :y
    t0 = time()
    try
        x, y = data.x, data.y
        ŷ = model(x)
        s = rel_l2(ŷ, y)
        wall = time() - t0
        meta = Dict{String,Any}("default_scorer" => "rel_l2")
        return ExperimentResult(s, wall, meta)
    catch e
        wall = time() - t0
        meta = Dict{String,Any}("error" => string(e))
        return ExperimentResult(Inf, wall, meta)
    end
end

# ---------------------------------------------------------------------------
# Default scorers
# ---------------------------------------------------------------------------

"""
    rel_l2(û, u) -> Float64

Relative L2 error:  ‖û − u‖₂ / ‖u‖₂

The primary SciML metric for trajectory/solution surrogates.  Scale-independent
and comparable across systems with different solution magnitudes.

Returns Inf when ‖u‖₂ ≈ 0 (degenerate reference).

Usage:
    score = rel_l2(predicted_trajectory, reference_trajectory)
"""
function rel_l2(û, u)::Float64
    denom = norm(u)
    denom < eps(Float64) && return Inf
    return norm(û .- u) / denom
end

"""
    quantum_advantage(cost_q, cost_classical_baseline) -> NamedTuple

Computes the quantum advantage ratio:  score = cost_q / cost_classical_baseline

    score < 1  ⇒  quantum is cheaper  (advantage demonstrated)
    score = 1  ⇒  equivalent
    score > 1  ⇒  classical is cheaper (no advantage)

Returns a NamedTuple:
    (ratio::Float64, meta::Dict{String,Any})

Candor rule (§5): if cost_classical_baseline is nothing / NaN / 0, returns
    (NaN, Dict("no_baseline" => true, "speculative" => true))
The poller reads "no_baseline" => true and logs "speculative, no advantage
demonstrated" in the ledger.  /phd:verify will refuse to mark such a result
KEPT-WITH-ADVANTAGE.

Usage:
    ra = quantum_advantage(circuit_cost, classical_cost)
    # populate meta before building ExperimentResult:
    meta["quantum_advantage_ratio"] = ra.ratio
    merge!(meta, ra.meta)
"""
function quantum_advantage(
    cost_q,
    cost_classical_baseline,
)::@NamedTuple{ratio::Float64, meta::Dict{String,Any}}
    # Validate baseline
    baseline_missing =
        isnothing(cost_classical_baseline) ||
        (cost_classical_baseline isa Number && isnan(cost_classical_baseline)) ||
        (cost_classical_baseline isa Number && cost_classical_baseline == 0)

    if baseline_missing
        meta = Dict{String,Any}(
            "no_baseline"  => true,
            "speculative"  => true,
            "warning"      => "quantum_advantage requires a fairly-tuned classical " *
                              "baseline; result is speculative. /phd:verify will not " *
                              "mark this KEPT-WITH-ADVANTAGE.",
        )
        return (ratio = NaN, meta = meta)
    end

    cq = Float64(cost_q)
    cb = Float64(cost_classical_baseline)
    ratio = cq / cb

    advantage = ratio < 1.0
    meta = Dict{String,Any}(
        "no_baseline"            => false,
        "speculative"            => false,
        "cost_q"                 => cq,
        "cost_classical_baseline"=> cb,
        "advantage_demonstrated" => advantage,
    )
    return (ratio = ratio, meta = meta)
end

# ---------------------------------------------------------------------------
# Multi-seed aggregation (Slice 4 — statistical rigor)
# ---------------------------------------------------------------------------

"""
    aggregate(scores::AbstractVector{<:Real}) -> NamedTuple

Aggregate K per-seed scores of one hypothesis into a robust summary. A single-seed
result is no result (reproducibility checklists require mean ± std over seeds), so
the loop runs K seeds and keeps on the aggregate.

Returns `(mean::Float64, std::Float64, n::Int)`.
  - n == 0           → mean = Inf, std = NaN (nothing to aggregate).
  - n == 1           → std = 0.0 (single sample, no spread).
  - Inf/NaN scores   → dropped before aggregating (a crashed seed shouldn't poison
                       the mean); n reflects the count of *valid* scores.
"""
function aggregate(scores::AbstractVector{<:Real})::@NamedTuple{mean::Float64, std::Float64, n::Int}
    valid = Float64[s for s in scores if !isnan(s) && !isinf(s)]
    n = length(valid)
    n == 0 && return (mean = Inf, std = NaN, n = 0)
    n == 1 && return (mean = valid[1], std = 0.0, n = 1)
    return (mean = mean(valid), std = std(valid), n = n)   # std = sample std (n-1)
end

# Pure-Julia log-gamma (Lanczos) — dependency-free, accurate enough for p-values.
const _LANCZOS = (0.99999999999980993, 676.5203681218851, -1259.1392167224028,
    771.32342877765313, -176.61502916214059, 12.507343278686905,
    -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7)
function _lgamma(x::Float64)::Float64
    x < 0.5 && return log(π / sin(π * x)) - _lgamma(1.0 - x)   # reflection
    x -= 1.0
    a = _LANCZOS[1]
    for i in 2:9; a += _LANCZOS[i] / (x + (i - 1)); end
    t = x + 7.5
    return 0.5 * log(2π) + (x + 0.5) * log(t) - t + log(a)
end

# Continued-fraction for the incomplete beta (Numerical Recipes), pure Julia.
function _betacf(a::Float64, b::Float64, x::Float64)::Float64
    tiny = 1e-30
    qab = a + b; qap = a + 1.0; qam = a - 1.0
    c = 1.0; d = 1.0 - qab * x / qap
    abs(d) < tiny && (d = tiny); d = 1.0 / d; h = d
    for m in 1:300
        m2 = 2m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d; abs(d) < tiny && (d = tiny)
        c = 1.0 + aa / c; abs(c) < tiny && (c = tiny)
        d = 1.0 / d; h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d; abs(d) < tiny && (d = tiny)
        c = 1.0 + aa / c; abs(c) < tiny && (c = tiny)
        d = 1.0 / d; del = d * c; h *= del
        abs(del - 1.0) < 1e-12 && break
    end
    return h
end

"""Regularized incomplete beta I_x(a,b) ∈ [0,1] — pure Julia, no SpecialFunctions dep."""
function _betai(a::Float64, b::Float64, x::Float64)::Float64
    x <= 0.0 && return 0.0
    x >= 1.0 && return 1.0
    bt = exp(_lgamma(a + b) - _lgamma(a) - _lgamma(b) + a * log(x) + b * log1p(-x))
    return x < (a + 1.0) / (a + b + 2.0) ? bt * _betacf(a, b, x) / a :
                                           1.0 - bt * _betacf(b, a, 1.0 - x) / b
end

"""
    welch_t(m1,s1,n1, m2,s2,n2) -> (t, df, p)

Welch's two-sample t-test (unequal variances) with Welch–Satterthwaite dof and a
two-sided p-value. Returns NaNs if either group has n<2 or zero pooled variance.
"""
function welch_t(m1::Real, s1::Real, n1::Integer, m2::Real, s2::Real, n2::Integer)::@NamedTuple{t::Float64, df::Float64, p::Float64}
    (n1 < 2 || n2 < 2) && return (t = NaN, df = NaN, p = NaN)
    v1 = s1^2 / n1; v2 = s2^2 / n2
    se = sqrt(v1 + v2)
    se == 0.0 && return (t = NaN, df = NaN, p = NaN)
    t  = (m1 - m2) / se
    df = (v1 + v2)^2 / (v1^2 / (n1 - 1) + v2^2 / (n2 - 1))
    p  = _betai(df / 2.0, 0.5, df / (df + t^2))   # two-sided
    return (t = Float64(t), df = Float64(df), p = Float64(p))
end

"""
    is_improvement_agg(new_mean,new_std,new_n, best_mean,best_std,best_n; alpha=0.05) -> NamedTuple

Keep/discard decision on aggregated multi-seed results.  Returns
`(keep::Bool, significant::Bool, p::Float64)`.

  - keep        : strict `new_mean < best_mean` (ties go to discard — simpler wins).
                  A first result (best_mean = Inf/NaN) always keeps. Significance does
                  NOT gate keeping — the loop still explores small gains.
  - significant : `keep && Welch p < alpha`, when both groups have n≥2. Falls back to a
                  transparent ~1σ separation when either n<2 (single-seed best / lost
                  seeds), reporting `p = NaN`. Flagged honestly so /phd:verify and
                  /phd:write don't overclaim a within-noise improvement.
  - p           : the two-sided Welch p-value (NaN when not computable).
"""
function is_improvement_agg(
    new_mean::Real, new_std::Real, new_n::Integer,
    best_mean::Real, best_std::Real, best_n::Integer;
    alpha::Float64 = 0.05,
)::@NamedTuple{keep::Bool, significant::Bool, p::Float64}
    (isnan(new_mean) || isinf(new_mean)) && return (keep = false, significant = false, p = NaN)
    if isnan(best_mean) || isinf(best_mean)         # first result
        return (keep = true, significant = true, p = NaN)
    end
    keep = new_mean < best_mean
    if new_n >= 2 && best_n >= 2 && !isnan(new_std) && !isnan(best_std)
        w = welch_t(new_mean, new_std, new_n, best_mean, best_std, best_n)
        return (keep = keep, significant = keep && !isnan(w.p) && w.p < alpha, p = w.p)
    end
    # Fallback: no variance estimate (single seed somewhere) → ~1σ heuristic.
    sep   = best_mean - new_mean
    noise = max(isnan(new_std) ? 0.0 : new_std, isnan(best_std) ? 0.0 : best_std)
    return (keep = keep, significant = keep && (sep > noise), p = NaN)
end

end # module MetricContract
