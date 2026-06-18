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

export ExperimentResult, evaluate, rel_l2, quantum_advantage

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

end # module MetricContract
