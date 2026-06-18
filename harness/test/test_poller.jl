using Test

include(joinpath(HARNESS, "poller.jl"))   # also brings jobctl + metric

# Helper: write a child seed-job (job.json + result.json + DONE status).
function _mk_child(groupdir, sub, seed, score)
    c = joinpath(groupdir, sub); mkpath(c)
    _jc_write_json_atomic(joinpath(c, "job.json"),
        Dict{String,Any}("hid"=>basename(groupdir), "seed"=>seed, "group"=>basename(groupdir),
                         "budget_s"=>10, "max_epochs"=>50))
    _jc_write_json_atomic(joinpath(c, "result.json"),
        Dict{String,Any}("hid"=>basename(groupdir), "score"=>score, "wall_s"=>1.0,
                         "backend"=>"cpu", "meta"=>Dict{String,Any}("no_baseline"=>true)))
    _jc_write_atomic(joinpath(c, "status"), "DONE")
    return c
end

@testset "poller.jl" begin
    @testset "is_improvement (single-seed)" begin
        @test is_improvement(0.02, 0.03)                 # strictly better
        @test !is_improvement(0.03, 0.03)                # tie → discard
        @test is_improvement(0.5, Inf)                   # first result (best=Inf)
        @test !is_improvement(NaN, 0.1) && !is_improvement(Inf, 0.1)
    end

    @testset "_seeds_for_group" begin
        s = _seeds_for_group(3, 0)
        @test length(s) == 3 && length(unique(s)) == 3 && !(1337 in s)
        @test _seeds_for_group(3, 0) == s                # deterministic
        @test all(!(1337 in _seeds_for_group(4, i)) for i in 0:20)   # never 1337
    end

    @testset "build_ledger_row" begin
        job = Dict{String,Any}("hypothesis"=>"h", "change"=>"c", "seed"=>42,
                               "budget_s"=>300, "metric_name"=>"rel_l2")
        res = Dict{String,Any}("score"=>0.029, "meta"=>Dict{String,Any}("no_baseline"=>true))
        # single-seed shape: "seed:" and no "± std"
        single = build_ledger_row("KEPT", "h001", job, res, Inf, "/tmp"; note="n")
        @test occursin("## H-001", single) && occursin("seed: 42", single)
        @test !occursin("±", single)
        # multi-seed shape: "± std", "n=", "seeds:"
        multi = build_ledger_row("KEPT", "h002", job, res, 0.05, "/tmp";
                                 note="n", score_std=0.004, n_seeds=5, seeds=[42,7,2024,314,99])
        @test occursin("± 0.004", multi) && occursin("n=5", multi) && occursin("seeds: 42,7,2024,314,99", multi)
        @test !occursin("1337", multi)
    end

    @testset "median_epoch_time" begin
        mktempdir() do d
            ed = joinpath(d, "epoch"); mkpath(ed)
            for (i, w) in enumerate([0.1, 0.3, 0.2])
                _jc_write_json_atomic(joinpath(ed, "000$(i).json"),
                    Dict{String,Any}("epoch"=>i, "wall_s"=>w))
            end
            @test isapprox(median_epoch_time(d), 0.2; atol=1e-9)
            @test isnan(median_epoch_time(joinpath(d, "nonexistent")))
        end
    end

    @testset "reap_group_done (fixture; launch_next=false)" begin
        mktempdir() do d
            write(joinpath(d, "LEDGER.md"),
                  "# Ledger\n\n<!-- Experiment rows are appended below this line -->\n")
            g = joinpath(d, "runs", "h001"); mkpath(g)
            _jc_write_json_atomic(joinpath(g, "group.json"),
                Dict{String,Any}("hid"=>"h001", "n_seeds"=>3, "metric_name"=>"rel_l2",
                                 "hypothesis"=>"test", "change"=>"baseline"))
            _mk_child(g, "s1", 42, 0.030)
            _mk_child(g, "s2", 7,  0.031)
            _mk_child(g, "s3", 2024, 0.029)

            reap_group_done(g, d; launch_next=false)         # no spawning

            # exactly one ledger row, KEPT, mean≈0.030 ± std, n=3, seeds without 1337
            txt = read(joinpath(d, "LEDGER.md"), String)
            body = split(txt, "appended below this line")[2]
            @test count(l -> startswith(l, "## H-"), split(body, '\n')) == 1
            @test occursin("KEPT", body) && occursin("± ", body) && occursin("n=3", body)
            @test occursin("seeds: 42,7,2024", body) && !occursin("1337", body)

            # best.json updated with mean/std/n
            best = read_best(d)
            @test best["hid"] == "h001" && isapprox(Float64(best["mean"]), 0.030; atol=1e-3)
            @test best["n"] == 3

            # next group NOT launched (launch_next=false)
            @test !isdir(joinpath(d, "runs", "h002"))
        end
    end

    @testset "reap_group_done (worse mean → DISCARDED)" begin
        mktempdir() do d
            write(joinpath(d, "LEDGER.md"),
                  "# Ledger\n\n<!-- Experiment rows are appended below this line -->\n")
            mkpath(joinpath(d, "runs"))
            _jc_write_json_atomic(joinpath(d, "runs", "best.json"),
                Dict{String,Any}("hid"=>"h000", "score"=>0.01, "mean"=>0.01, "std"=>0.001, "n"=>3))
            g = joinpath(d, "runs", "h001"); mkpath(g)
            _jc_write_json_atomic(joinpath(g, "group.json"),
                Dict{String,Any}("hid"=>"h001", "n_seeds"=>3))
            _mk_child(g, "s1", 42, 0.05); _mk_child(g, "s2", 7, 0.06); _mk_child(g, "s3", 2024, 0.055)
            reap_group_done(g, d; launch_next=false)
            body = split(read(joinpath(d, "LEDGER.md"), String), "appended below this line")[2]
            @test occursin("DISCARDED", body)
            @test read_best(d)["hid"] == "h000"              # best unchanged
        end
    end
end
