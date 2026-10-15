# timing-probe.jl — times the endpoints in-process, no port bound (2026-09-15).
#
# RUN (never against the real books):
#   set LEDGER_ROOT to an EMPTY scratch folder, then from this folder:
#   julia --startup-file=no timing-probe.jl              # warm  — what start() does
#   LDGR_NO_WARMUP=1 julia --startup-file=no timing-probe.jl   # cold — no warm-up
#
# It includes ../server.jl, runs warmup() unless LDGR_NO_WARMUP=1 is set (the
# same switch start() honours, so a cold run needs no edit to this file), then
# times the FIRST call of each kind of check, save and next, i.e. what the person
# pressing a button feels. The first call of each shape is the only one that
# matters: every later one is already compiled.
using Dates
include(joinpath(@__DIR__, "..", "server.jl"))
println("ROOT = ", Layout.ROOT)
basename(Layout.ROOT) == "Records" && error("LEDGER_ROOT points at the real books; set it to a scratch folder")
if get(ENV, "LDGR_NO_WARMUP", "") == "1"
    println("warmup() SKIPPED (LDGR_NO_WARMUP=1) — these are the cold numbers\n")
else
    t0 = time(); warmup(); println("warmup() took ", round(time()-t0, digits=1), " s\n")
end
using JSON3, HTTP
post(path, body) = router(HTTP.Request("POST", path, ["Content-Type"=>"application/json"], JSON3.write(body)))
get_(path) = router(HTTP.Request("GET", path))
amounts(; o=1270.0, s=98400.0, e=22400.0, dep=75000.0, b=0.0, c=o+1000.0) =
    Dict("opening_balance"=>o, "cash_sales"=>s, "POS_Scotia"=>0, "POS_RBL"=>0, "POS_U"=>0,
         "doctor_fees"=>e, "medical_supply_costs"=>0, "miscellaneous_costs"=>0, "taxi_fare"=>0,
         "deposits"=>dep, "Mr_Boyle"=>b, "closing_balance"=>c)

function timed(label, f)
    t = @elapsed r = f()
    println(rpad(label, 46), lpad(string(round(Int, t*1000)), 7), " ms  status=", r.status)
    r
end
d1 = Date(2026, 8, 1)
timed("POST /api/check genesis (first real)",    () -> post("/api/check", (date=string(d1), amounts=amounts())))
timed("POST /api/save genesis (FIRST REAL)",     () -> post("/api/save", (date=string(d1), amounts=amounts(), allowGenesis=true)))
d2 = d1 + Day(1)
timed("POST /api/check day2",                    () -> post("/api/check", (date=string(d2), amounts=amounts(o=2270.0))))
timed("POST /api/save day2",                     () -> post("/api/save", (date=string(d2), amounts=amounts(o=2270.0))))
d3 = d2 + Day(1)
timed("POST /api/check day3 unbalanced (first)", () -> post("/api/check", (date=string(d3), amounts=amounts(o=3270.0, c=4000.0), reason="x")))
timed("POST /api/save day3 unbalanced (first)",  () -> post("/api/save", (date=string(d3), amounts=amounts(o=3270.0, c=4000.0), reason="x")))
timed("POST /api/save day3 refused (no reason)", () -> post("/api/save", (date=string(d3), amounts=amounts(o=3270.0, c=4000.0))))
timed("POST /api/save day3 refused (Stop)",      () -> post("/api/save", (date=string(d3), amounts=amounts(o=3270.0, dep=900000.0))))
d4 = d3 + Day(1)
timed("POST /api/save day4 OFF day (first)",     () -> post("/api/save", (date=string(d4), status="closed")))
timed("POST /api/save day2 edit, no force",      () -> post("/api/save", (date=string(d2), amounts=amounts(o=2270.0))))
timed("POST /api/save day2 edit, force",         () -> post("/api/save", (date=string(d2), amounts=amounts(o=2270.0), force=true)))
timed("GET /api/day (saved day)",                () -> get_("/api/day?date=$(d2)"))

# --- Next day, in its three answers -----------------------------------------
# Save and Next day are two buttons now, so the wait after Next day is its own
# number. Each of the three answers is a separate first call: not saved at all,
# saved but changed on screen, and saved exactly as shown.
d5 = d4 + Day(1)                      # never saved
timed("POST /api/next  not saved (first)",       () -> post("/api/next", (date=string(d5), amounts=amounts(o=4270.0))))
timed("POST /api/next  saved but changed",       () -> post("/api/next", (date=string(d2), amounts=amounts(o=2270.0, c=9999.0), reason="x")))
timed("POST /api/next  saved and unchanged",     () -> post("/api/next", (date=string(d2), amounts=amounts(o=2270.0))))
