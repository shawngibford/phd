using Test

include(joinpath(HARNESS, "jobctl.jl"))

@testset "jobctl.jl" begin
    @testset "JSON round-trip" begin
        mktempdir() do d
            p = joinpath(d, "x.json")
            orig = Dict{String,Any}("a"=>1, "b"=>2.5, "c"=>"hi", "ok"=>true,
                                    "nil"=>nothing, "nested"=>Dict{String,Any}("k"=>"v", "m"=>3))
            _jc_write_json_atomic(p, orig)
            got = _jc_read_json(p)
            @test got["a"] == 1 && got["b"] == 2.5 && got["c"] == "hi"
            @test got["ok"] == true && got["nil"] === nothing
            @test got["nested"] isa Dict && got["nested"]["k"] == "v" && got["nested"]["m"] == 3
        end
    end

    @testset "id helpers" begin
        @test _hid_to_ledger("h007") == "H-007"
        @test _hid_to_ledger("h100") == "H-100"
    end
    # (_seeds_for_group lives in poller.jl — tested in test_poller.jl)

    @testset "_next_hid" begin
        mktempdir() do d
            @test _next_hid(d) == "h001"                      # no runs/
            mkpath(joinpath(d, "runs", "h001")); mkpath(joinpath(d, "runs", "h004"))
            @test _next_hid(d) == "h005"                      # max+1
        end
    end

    @testset "scan_job_dirs + group helpers" begin
        mktempdir() do d
            runs = joinpath(d, "runs"); mkpath(runs)
            # flat legacy job
            mkpath(joinpath(runs, "h001")); touch(joinpath(runs, "h001", "job.json"))
            # group h002 with 2 children
            mkpath(joinpath(runs, "h002")); touch(joinpath(runs, "h002", "group.json"))
            for s in ("s1","s2")
                mkpath(joinpath(runs, "h002", s)); touch(joinpath(runs, "h002", s, "job.json"))
            end
            dirs = scan_job_dirs(d)
            @test joinpath(runs, "h001") in dirs
            @test joinpath(runs, "h002", "s1") in dirs && joinpath(runs, "h002", "s2") in dirs
            @test !(joinpath(runs, "h002") in dirs)           # group dir itself is not a job
            @test is_group_child(joinpath(runs, "h002", "s1"))
            @test !is_group_child(joinpath(runs, "h001"))
            @test length(group_children(joinpath(runs, "h002"))) == 2
        end
    end

    @testset "append_ledger_row (mkdir lock acquire/release)" begin
        mktempdir() do d
            led = joinpath(d, "LEDGER.md")
            write(led, "# Ledger\n\n<!-- Experiment rows are appended below this line -->\n")
            append_ledger_row(d, "## H-001 · 2026-06-18 · KEPT\nnote: x")
            append_ledger_row(d, "## H-002 · 2026-06-18 · KEPT\nnote: y")
            txt = read(led, String)
            @test occursin("H-001", txt) && occursin("H-002", txt)   # both rows landed intact
            @test !isdir(led * ".lock")                              # lock released each time
        end
    end
end
