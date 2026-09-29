# =============================================================================
# test_checks_titles.jl — every warning code raised in Checks.jl has a short
# title for the form's Checks panel.
#
# Run:  julia test_checks_titles.jl      (with this file placed next to Checks.jl)
#
# The codes are read out of Checks.jl's own source rather than copied into a
# list here, so a new Finding("L…") added without a title fails this test
# instead of reaching the form with a blank label. Writes nothing.
# =============================================================================

include("Config.jl");   using .Config
include("getdate.jl");  using .getdate
include("DayInput.jl"); using .DayInput
include("Checks.jl");   using .Checks

const PASS = Ref(0); const FAIL = Ref(0)

function ok(label, cond)
    cond ? (PASS[] += 1; println("  PASS  $label")) : (FAIL[] += 1; println("  FAIL  $label"))
end

println("\n", repeat("=", 70), "\n  LDGR v4.0 WARNING TITLES\n", repeat("=", 70))

src   = read(joinpath(@__DIR__, "Checks.jl"), String)
codes = unique([m.captures[1] for m in eachmatch(r"Finding\(\"(L\d-[A-Z0-9]+)\"", src)])

println("\nEvery code raised in Checks.jl")
ok("found codes to check ($(length(codes)): $(join(codes, ", ")))", !isempty(codes))
for code in codes
    t = finding_title(code)
    ok("$code has a title  [\"$t\"]", !isempty(t))
end

println("\nThe newest code, spelled out rather than only discovered above")
ok("L3-E is titled for its row  [\"$(finding_title("L3-E"))\"]",
   finding_title("L3-E") == "Day after already on record")
ok("and it is one of the codes Checks.jl raises", "L3-E" in codes)

println("\nA blank balance is titled after its own box")
for k in CASH_BOOK_KEYS
    t = finding_title(Finding("L1-C", LEVEL_STOP, k, ""))
    ok("L1-C on $k  [\"$t\"]", t == "$(label_of(k)) Not Entered")
end
ok("any other finding takes its code's title",
   finding_title(Finding("L2-A", LEVEL_EXPLAIN, :closing_balance, "")) == finding_title("L2-A"))

println("\nUnknown code")
ok("finding_title(\"XX-9\") is empty", finding_title("XX-9") == "")

println("\n", repeat("=", 70))
println("  PASSED $(PASS[])   FAILED $(FAIL[])")
println(repeat("=", 70))
exit(FAIL[] == 0 ? 0 : 1)
