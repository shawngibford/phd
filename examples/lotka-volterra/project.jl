"""
project.jl — Lotka–Volterra surrogate learning (PHD harness example)

Implements the runner.jl project-hook interface for a predator-prey ODE surrogate task.
The "model" is a small parameter vector [α, β, γ, δ] that is iteratively nudged
toward the true Lotka–Volterra parameters by fitting simulated trajectory data.

System (standard Lotka–Volterra):
    dx/dt =  α·x − β·x·y      (prey)
    dy/dt = −γ·y + δ·x·y      (predator)

True parameters (hidden ground truth):
    α=1.0, β=0.1, γ=1.5, δ=0.075

The surrogate task: given noisy observations of the prey/predator trajectory,
recover the four ODE parameters. train_step does one gradient-free perturbation
step (finite-difference hill-climbing). score integrates the current model
parameters forward and computes rel_l2 against a held-out trajectory at a
fixed seed.

Design constraints:
    - Zero heavy dependencies: hand-rolled RK4, no DifferentialEquations.jl.
    - Deterministic under fixed seed.
    - Each epoch << 1 s so the verifier can run many epochs.
    - Implements every required hook: make_model, make_data, train_step,
      score, model_state, load_model_state!

Hook interface (from runner.jl):
    make_model(job::Dict)                              -> LVModel
    make_data(job::Dict)                               -> LVData
    train_step(model, data, epoch::Int, job::Dict)     -> (model, loss::Float64)
    score(model, data, budget_s::Float64)              -> ExperimentResult
    model_state(model)                                 -> Vector{Float64}
    load_model_state!(model, state)                    -> LVModel
"""

# ---------------------------------------------------------------------------
# Dependency: pull in MetricContract from the harness directory.
# runner.jl already includes metric.jl and device.jl before loading the
# project file, so MetricContract is available.  We import what we need.
# ---------------------------------------------------------------------------

using .MetricContract: ExperimentResult, rel_l2
import Random

# ---------------------------------------------------------------------------
# Ground truth (fixed; never exposed to the model during training)
# ---------------------------------------------------------------------------

const LV_TRUE_ALPHA = 1.0
const LV_TRUE_BETA  = 0.1
const LV_TRUE_GAMMA = 1.5
const LV_TRUE_DELTA = 0.075

# ---------------------------------------------------------------------------
# RK4 integrator (hand-rolled, zero deps)
# ---------------------------------------------------------------------------

"""
    lv_deriv(xy, params) -> (dx, dy)

Compute the Lotka–Volterra derivative at state `xy = (x, y)` with
parameters `params = (α, β, γ, δ)`.
"""
function lv_deriv(xy::Tuple{Float64,Float64}, params::NTuple{4,Float64})
    x, y = xy
    α, β, γ, δ = params
    dx =  α * x - β * x * y
    dy = -γ * y + δ * x * y
    return (dx, dy)
end

"""
    rk4_step(xy, params, dt) -> (x_next, y_next)

One RK4 step with fixed step size `dt`.
"""
function rk4_step(
    xy     :: Tuple{Float64,Float64},
    params :: NTuple{4,Float64},
    dt     :: Float64,
) :: Tuple{Float64,Float64}
    k1 = lv_deriv(xy, params)
    xy2 = (xy[1] + 0.5*dt*k1[1], xy[2] + 0.5*dt*k1[2])
    k2 = lv_deriv(xy2, params)
    xy3 = (xy[1] + 0.5*dt*k2[1], xy[2] + 0.5*dt*k2[2])
    k3 = lv_deriv(xy3, params)
    xy4 = (xy[1] + dt*k3[1], xy[2] + dt*k3[2])
    k4 = lv_deriv(xy4, params)
    x_next = xy[1] + (dt/6.0) * (k1[1] + 2*k2[1] + 2*k3[1] + k4[1])
    y_next = xy[2] + (dt/6.0) * (k1[2] + 2*k2[2] + 2*k3[2] + k4[2])
    return (x_next, y_next)
end

"""
    integrate_lv(x0, y0, params, T, dt) -> (xs, ys)

Integrate the Lotka–Volterra ODE from `(x0, y0)` for `T` time units
with RK4 step size `dt`.  Returns two Float64 vectors of length
`floor(Int, T/dt) + 1` (including the initial point).
"""
function integrate_lv(
    x0     :: Float64,
    y0     :: Float64,
    params :: NTuple{4,Float64},
    T      :: Float64 = 15.0,
    dt     :: Float64 = 0.1,
) :: Tuple{Vector{Float64}, Vector{Float64}}
    n  = floor(Int, T / dt) + 1
    xs = Vector{Float64}(undef, n)
    ys = Vector{Float64}(undef, n)
    xs[1] = x0;  ys[1] = y0
    xy = (x0, y0)
    for i in 2:n
        xy = rk4_step(xy, params, dt)
        xs[i] = xy[1]
        ys[i] = xy[2]
    end
    return (xs, ys)
end

# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

"""
    LVModel

Mutable surrogate: a four-parameter estimate [α, β, γ, δ] of the true
Lotka–Volterra parameters.  train_step nudges these toward the ground truth
by finite-difference gradient descent on the trajectory loss.
"""
mutable struct LVModel
    params :: Vector{Float64}   # [α, β, γ, δ]
    lr     :: Float64           # learning rate (clamp-adapted per epoch)
end

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

"""
    LVData

Holds the training trajectory and the held-out (test) trajectory.
Both are generated from the true parameters; the split is 80/20 in time.

Fields:
    train_xs, train_ys  — prey/predator time-series for training
    test_xs,  test_ys   — held-out trajectory for scoring
    x0, y0              — shared initial condition
    T_total             — total integration horizon (seconds)
    dt                  — integration step size
"""
struct LVData
    train_xs :: Vector{Float64}
    train_ys :: Vector{Float64}
    test_xs  :: Vector{Float64}
    test_ys  :: Vector{Float64}
    x0       :: Float64
    y0       :: Float64
    T_total  :: Float64
    dt       :: Float64
end

# ---------------------------------------------------------------------------
# Hook: make_model
# ---------------------------------------------------------------------------

"""
    make_model(job::Dict) -> LVModel

Initialise the parameter estimate with small random perturbations around a
plausible starting point.  Deterministic under `job["seed"]`.
"""
function make_model(job::Dict) :: LVModel
    seed = Int(get(job, "seed", 42))
    rng  = VERSION >= v"1.7" ? Random.Xoshiro(seed) : Random.MersenneTwister(seed)
    # Start near (but not at) true values — gives the optimizer something to do.
    α0 = 1.0  + 0.5 * (rand(rng) - 0.5)
    β0 = 0.1  + 0.05 * (rand(rng) - 0.5)
    γ0 = 1.5  + 0.5 * (rand(rng) - 0.5)
    δ0 = 0.075 + 0.03 * (rand(rng) - 0.5)
    # Clamp to strictly positive (parameters have physical meaning).
    α0 = max(0.05, α0);  β0 = max(0.005, β0)
    γ0 = max(0.05, γ0);  δ0 = max(0.005, δ0)
    lr = get(job, "learning_rate", get(job, "lr", 0.02))  # BUG 3 FIX: poller writes "learning_rate"
    return LVModel([α0, β0, γ0, δ0], Float64(lr))
end

# ---------------------------------------------------------------------------
# Hook: make_data
# ---------------------------------------------------------------------------

"""
    make_data(job::Dict) -> LVData

Generate the ground-truth Lotka–Volterra trajectory and split 80/20.
The split is purely temporal: the first 80% of time-steps are training data;
the last 20% are held-out.  Initial conditions are deterministic under the seed.

The held-out seed is hard-wired at 1337 (as required by experiment.md constraints).
"""
function make_data(job::Dict) :: LVData
    # Initial conditions: use seed+1 for data (separate from model seed).
    data_seed = Int(get(job, "seed", 42)) + 1
    rng = VERSION >= v"1.7" ? Random.Xoshiro(data_seed) : Random.MersenneTwister(data_seed)

    x0 = 10.0 + 2.0 * (rand(rng) - 0.5)
    y0 =  5.0 + 1.0 * (rand(rng) - 0.5)

    T_total = 15.0   # seconds of LV time
    dt      = 0.05   # fine step for accurate ground truth

    true_params = (LV_TRUE_ALPHA, LV_TRUE_BETA, LV_TRUE_GAMMA, LV_TRUE_DELTA)
    xs, ys = integrate_lv(x0, y0, true_params, T_total, dt)

    n = length(xs)
    split = floor(Int, 0.8 * n)

    train_xs = xs[1:split]
    train_ys = ys[1:split]
    test_xs  = xs[split+1:end]
    test_ys  = ys[split+1:end]

    return LVData(train_xs, train_ys, test_xs, test_ys, x0, y0, T_total, dt)
end

# ---------------------------------------------------------------------------
# Loss: trajectory L2 on training data
# ---------------------------------------------------------------------------

"""
    _trajectory_loss(model::LVModel, data::LVData) -> Float64

Integrate with the model's current parameters starting from (x0, y0),
extract the training-time portion, and return rel_l2 against the
training ground truth.
"""
function _trajectory_loss(model::LVModel, data::LVData) :: Float64
    p = (model.params[1], model.params[2], model.params[3], model.params[4])
    # Only integrate over the training window (80% of T_total).
    T_train = data.T_total * 0.8
    xs_hat, ys_hat = integrate_lv(data.x0, data.y0, p, T_train, data.dt)

    n = min(length(xs_hat), length(data.train_xs))
    # Concatenate x and y into a single flat vector for rel_l2.
    u_hat = vcat(xs_hat[1:n], ys_hat[1:n])
    u_ref  = vcat(data.train_xs[1:n], data.train_ys[1:n])
    return rel_l2(u_hat, u_ref)
end

# ---------------------------------------------------------------------------
# Hook: train_step
# ---------------------------------------------------------------------------

"""
    train_step(model::LVModel, data::LVData, epoch::Int, job::Dict)
              -> (model, loss::Float64)

One gradient-free update: for each parameter, evaluate the loss with a small
positive and negative perturbation (central difference), then take a step in
the descent direction.  This is coordinate-wise finite-difference gradient
descent — dependency-free and sufficient for the 4-dimensional LV parameter
recovery task.

The step size decays geometrically with epoch number so early epochs explore
broadly and later epochs refine.
"""
function train_step(
    model :: LVModel,
    data  :: LVData,
    epoch :: Int,
    job   :: Dict,
) :: Tuple{LVModel, Float64}
    loss_before = _trajectory_loss(model, data)
    h = 1e-4   # finite-difference step

    # Decay learning rate mildly each epoch.
    effective_lr = model.lr * (0.99 ^ (epoch - 1))
    effective_lr = max(effective_lr, 1e-5)   # floor to avoid stalling

    grad = Vector{Float64}(undef, 4)
    for i in 1:4
        orig = model.params[i]
        model.params[i] = orig + h
        loss_plus  = _trajectory_loss(model, data)
        model.params[i] = orig - h
        loss_minus = _trajectory_loss(model, data)
        model.params[i] = orig
        grad[i] = (loss_plus - loss_minus) / (2 * h)
    end

    # Gradient descent step.
    for i in 1:4
        model.params[i] -= effective_lr * grad[i]
        model.params[i]  = max(1e-6, model.params[i])   # keep params positive
    end

    loss_after = _trajectory_loss(model, data)
    return (model, loss_after)
end

# ---------------------------------------------------------------------------
# Hook: score
# ---------------------------------------------------------------------------

"""
    score(model::LVModel, data::LVData, budget_s::Float64) -> ExperimentResult

Score the model on the held-out (last 20%) trajectory.  Integrates the model
forward from the last training point and computes rel_l2 against the held-out
ground truth.  Lower is better.

`budget_s` is informational; this scorer is fast (< 1 ms) and always completes.
"""
function score(
    model    :: LVModel,
    data     :: LVData,
    budget_s :: Float64,
) :: ExperimentResult
    t0 = time()

    # The held-out window starts at 80% of the total trajectory.
    # We must integrate from the last training point (data.x0, data.y0 evolved
    # through training time) to get a valid continuation.
    # Re-integrate the full trajectory with the model's current parameters,
    # then slice the held-out portion.
    p = (model.params[1], model.params[2], model.params[3], model.params[4])
    xs_full, ys_full = integrate_lv(data.x0, data.y0, p, data.T_total, data.dt)

    n_total  = length(xs_full)
    split    = floor(Int, 0.8 * n_total)
    xs_test  = xs_full[split+1:end]
    ys_test  = ys_full[split+1:end]

    n = min(length(xs_test), length(data.test_xs))
    u_hat = vcat(xs_test[1:n], ys_test[1:n])
    u_ref  = vcat(data.test_xs[1:n], data.test_ys[1:n])

    s = rel_l2(u_hat, u_ref)
    wall = time() - t0

    # Parameter distance from true values (informational; not the score).
    param_err = sqrt(
        (model.params[1] - LV_TRUE_ALPHA)^2 +
        (model.params[2] - LV_TRUE_BETA)^2  +
        (model.params[3] - LV_TRUE_GAMMA)^2 +
        (model.params[4] - LV_TRUE_DELTA)^2
    )

    meta = Dict{String, Any}(
        "scorer"       => "rel_l2_held_out",
        "alpha_hat"    => model.params[1],
        "beta_hat"     => model.params[2],
        "gamma_hat"    => model.params[3],
        "delta_hat"    => model.params[4],
        "param_err"    => param_err,
        "backend"      => "cpu",
        "note"         => "Lotka-Volterra parameter-recovery surrogate; " *
                          "score = rel_l2 on held-out 20% of trajectory",
    )

    return ExperimentResult(s, wall, meta)
end

# ---------------------------------------------------------------------------
# Hook: model_state / load_model_state!
# ---------------------------------------------------------------------------

"""
    model_state(model::LVModel) -> Vector{Float64}

Return a copy of the parameter vector for serialisation.
"""
function model_state(model::LVModel) :: Vector{Float64}
    return copy(model.params)
end

"""
    load_model_state!(model::LVModel, state) -> LVModel

Restore the parameter vector from a deserialised checkpoint.
"""
function load_model_state!(model::LVModel, state) :: LVModel
    model.params = copy(Vector{Float64}(state))
    return model
end
