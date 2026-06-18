"""
device.jl — CPU-only device layer (PHD harness, v1)

Public API
----------
    select_backend()         -> Symbol          # :cpu (always in v1)
    describe_device()        -> Dict{String,Any} # nthreads, blas_threads, cpu_model, hostname
    configure_threads!(; threads_per_exp=1) -> Nothing

Extension points (v2+)
----------------------
  Metal.jl (Apple GPU / MPS):
      import Metal
      if Metal.functional()
          return :metal
      end
  CUDA.jl:
      import CUDA
      if CUDA.functional()
          return :cuda
      end
  Add those branches in select_backend() BEFORE the fallthrough :cpu return.
  Record the returned symbol in job.json so the daemon can filter results by backend.
"""

module DeviceLayer

using LinearAlgebra: BLAS

export select_backend, describe_device, configure_threads!

# ---------------------------------------------------------------------------
# Backend selection
# ---------------------------------------------------------------------------

"""
    select_backend() -> Symbol

Returns the best available compute backend as a symbol.

v1: always :cpu — the mature, cross-platform path.

Extension points for v2+:
  - Insert a Metal.jl branch here for Apple GPU (MPS) support.
  - Insert a CUDA.jl branch for NVIDIA GPU support.
  Both require their respective packages to be loaded and functional.
  The caller (runner.jl) records the symbol in result.json / the ledger.

Example v2 extension (do NOT activate in v1):

    # Metal (Apple MPS) — slot in here:
    # try
    #     using Metal: functional as metal_functional
    #     metal_functional() && return :metal
    # catch
    # end

    # CUDA — slot in here:
    # try
    #     using CUDA: functional as cuda_functional
    #     cuda_functional() && return :cuda
    # catch
    # end
"""
function select_backend()::Symbol
    return :cpu
end

# ---------------------------------------------------------------------------
# Thread configuration
# ---------------------------------------------------------------------------

"""
    configure_threads!(; threads_per_exp::Int = 1) -> Nothing

Sets BLAS thread count to a sensible value given the Julia thread count and
how many parallel experiments are expected to share the machine.

    threads_per_exp — how many Julia threads a single experiment is expected
                      to use (for BLAS pinning). Set to 1 for parallel search
                      (K concurrent experiments), higher for single large jobs.

BLAS strategy:
  - We divide available threads evenly across concurrent experiments so that
    parallel search doesn't oversubscribe the core count.
  - Minimum 1 BLAS thread; maximum = Threads.nthreads().

On Apple Silicon the Accelerate BLAS is used automatically; thread count still
matters for throughput on non-trivially-sized matrices (>= 128x128).
"""
function configure_threads!(; threads_per_exp::Int = 1)::Nothing
    n = Threads.nthreads()
    blas_n = max(1, n ÷ max(1, threads_per_exp))
    BLAS.set_num_threads(blas_n)
    return nothing
end

# ---------------------------------------------------------------------------
# Device description
# ---------------------------------------------------------------------------

"""
    describe_device() -> Dict{String,Any}

Returns a snapshot of the compute environment. Recorded in job.json and
result.json so every ledger entry is reproducible on a different machine.

Keys always present:
  "backend"       => String  — selected backend ("cpu")
  "nthreads"      => Int     — Julia thread count (JULIA_NUM_THREADS)
  "blas_threads"  => Int     — current BLAS thread count (after configure_threads!)
  "hostname"      => String  — hostname (falls back to "unknown")
  "cpu_model"     => String  — CPU model string if discoverable, else "unknown"
  "julia_version" => String  — Julia version string
"""
function describe_device()::Dict{String,Any}
    d = Dict{String,Any}(
        "backend"       => string(select_backend()),
        "nthreads"      => Threads.nthreads(),
        "blas_threads"  => BLAS.get_num_threads(),
        "hostname"      => _hostname(),
        "cpu_model"     => _cpu_model(),
        "julia_version" => string(VERSION),
    )
    return d
end

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _hostname()::String
    try
        return strip(read(`hostname`, String))
    catch
        return "unknown"
    end
end

"""
Probe the CPU model string from OS-specific sources.
Gracefully returns "unknown" on any platform where the probe fails.
"""
function _cpu_model()::String
    # macOS: sysctl
    if Sys.isapple()
        try
            out = read(`sysctl -n machdep.cpu.brand_string`, String)
            s = strip(out)
            isempty(s) || return s
        catch end
        # Apple Silicon: machdep.cpu.brand_string may be absent; try hw.model
        try
            out = read(`sysctl -n hw.model`, String)
            s = strip(out)
            isempty(s) || return s
        catch end
        return "unknown"
    end

    # Linux: /proc/cpuinfo
    if Sys.islinux()
        try
            for line in eachline("/proc/cpuinfo")
                if startswith(line, "model name")
                    parts = split(line, ':', limit=2)
                    length(parts) == 2 && return strip(parts[2])
                end
            end
        catch end
        return "unknown"
    end

    return "unknown"
end

end # module DeviceLayer
