# =============================================================================
# test_endpoints.jl — the endpoints the form actually talks to.
#
# Run:  LEDGER_ROOT=/tmp/ldgr_endpoints julia test_endpoints.jl
#       (with this file placed next to server.jl)
#
# Writes to LEDGER_ROOT only. Never point this at the real Records folder.
#
# WHY THIS EXISTS. The other scripts in this folder test the bookkeeping
# underneath the form. server.jl is the only place the browser and the books
# meet, and therefore the only place a refusal can be got wrong in a way the
# operator sees. It is also where "Save" and "Next day" became two separate
# actions, and the whole point of POST /api/next is that it answers about the
# BOOKS rather than about anything the page remembers.
#
# NO PORT IS BOUND. The endpoints are called in-process, by handing `router` the
# same HTTP.Request a browser would produce. That is the whole request path —
# routing, JSON parsing, record_from_payload, the checks, process_day and the
# response — minus the socket. So two copies of this can run at once, nothing
# listens on 127.0.0.1, and the test cannot collide with a server the owner has
# open.
# =============================================================================

using Dates
include("server.jl")
using JSON3, HTTP

const PASS = Ref(0); const FAIL = Ref(0)

function ok(label, cond)
    cond ? (PASS[] += 1; println("  PASS  $label")) : (FAIL[] += 1; println("  FAIL  $label"))
end

# --- Calling an endpoint the way the browser does ---------------------------
post(path, body) = router(HTTP.Request("POST", path,
                          ["Content-Type" => "application/json"], JSON3.write(body)))
get_(path) = router(HTTP.Request("GET", path))
body_of(resp) = JSON3.read(String(resp.body))
keyset(o) = Set(String(k) for k in keys(o))

"The figures for one work day, in the shape app.js sends them. Predicted closing
is always the opening plus 1000, so `c` says whether the day balances."
figures(; o, s=98400.0, e=22400.0, dep=75000.0, b=0.0, c) = Dict(
    "opening_balance" => o, "cash_sales" => s,
    "POS_Scotia" => 0, "POS_RBL" => 0, "POS_U" => 0,
    "doctor_fees" => e, "medical_supply_costs" => 0,
    "miscellaneous_costs" => 0, "taxi_fare" => 0,
    "deposits" => dep, "Mr_Boyle" => b, "closing_balance" => c)

"Every finding carries exactly the six keys the form renders, and nothing else."
const FINDING_KEYS = Set(["code", "level", "levelName", "title", "field", "message"])
function findings_wellformed(fs)
    isempty(fs) && return false
    for f in fs
        keyset(f) == FINDING_KEYS || return false
        f.code isa AbstractString || return false
        f.level isa Integer || return false
        f.levelName isa AbstractString || return false
        f.title isa AbstractString || return false
        f.message isa AbstractString || return false
        # `field` is the box to jump to, or null for a finding about the whole day.
        (f.field === nothing || f.field isa AbstractString) || return false
    end
    return true
end

"Every file and folder under a root, with its size, so a change of any kind shows."
function tree(root)
    isdir(root) || return String[]
    out = String[]
    for (dir, dirs, files) in walkdir(root)
        for f in files; push!(out, joinpath(dir, f) * "  " * string(filesize(joinpath(dir, f)))); end
        for d in dirs;  push!(out, joinpath(dir, d) * "  <dir>"); end
    end
    return sort(out)
end

println("\n", repeat("=", 70), "\n  LDGR v4.0 SERVER ENDPOINTS\n  ROOT: $(Layout.ROOT)\n", repeat("=", 70))
basename(Layout.ROOT) == "Records" && error("LEDGER_ROOT points at the real books; set it to a scratch folder")

const D1 = Date(2026, 4, 1)    # the first day on record
const D2 = Date(2026, 4, 2)    # both differences, both reasons
const D3 = Date(2026, 4, 3)    # an Off day
const D4 = Date(2026, 4, 4)    # never saved
const D5 = Date(2026, 4, 5)    # fills the gap under D6
const D6 = Date(2026, 4, 6)    # saved before D5, so its ledger waits
const TODAY = Dates.today()    # saved last, so "the day after" has not happened

# =============================================================== /api/config
println("\nGET /api/config — the shape of the form")
r = get_("/api/config"); c = body_of(r)
ok("200", r.status == 200)
ok("ok true", c.ok === true)
ok("today is the machine's date", String(c.today) == string(TODAY))
ok("four groups, each with categories",
   length(c.groups) == 4 && all(g -> !isempty(g.categories), c.groups))
ok("every category has a key and a label",
   all(g -> all(x -> haskey(x, :key) && haskey(x, :label), g.categories), c.groups))
ok("keyOrder matches Config", [String(k) for k in c.keyOrder] == [String(k) for k in KEY_ORDER])
ok("depositKey is the deposits key", String(c.depositKey) == String(deposit[1].key))
ok("openingKey / closingKey are the cash book",
   String(c.openingKey) == "opening_balance" && String(c.closingKey) == "closing_balance")
ok("inflow and outflow keys sent", !isempty(c.inflowKeys) && !isempty(c.outflowKeys))
ok("a label for every journal key",
   all(k -> haskey(c.labels, Symbol(colname_of(k))), JOURNAL_KEYS))

# ================================================================ /api/check
println("\nPOST /api/check — the first day, before anything is saved")
r = post("/api/check", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
b = body_of(r)
ok("200", r.status == 200)
ok("exactly the keys app.js reads",
   keyset(b) == Set(["ok", "findings", "predicted", "available", "paidOut",
                     "needsReason", "blocked", "genesis", "hasDailyLedger", "inBooks"]))
ok("genesis true — nothing is on record before it", b.genesis === true)
ok("not blocked, no reason needed", b.blocked === false && b.needsReason === false)
ok("not in the books, no ledger yet", b.inBooks === false && b.hasDailyLedger === false)
ok("predicted closing is opening + 1000", abs(b.predicted - 2270.0) < 0.005)
ok("available and paidOut are the two sides of it",
   abs(b.available - 99670.0) < 0.005 && abs(b.paidOut - 97400.0) < 0.005)
ok("findings well formed, and L3-D is among them",
   findings_wellformed(b.findings) && any(f -> f.code == "L3-D", b.findings))

println("\nPOST /api/check — a blank balance")
r = post("/api/check", (date=string(D1), amounts=figures(o=1270.0, c="")))
b = body_of(r)
ok("a blank closing balance → 200 and blocked", r.status == 200 && b.blocked === true)
ok("L1-C names the closing balance box",
   any(f -> f.code == "L1-C" && f.field == "closing_balance", b.findings))
ok("the prediction still stands — it is not made from the count",
   abs(b.predicted - 2270.0) < 0.005)

r = post("/api/check", (date=string(D1), amounts=figures(o="", c=2270.0)))
b = body_of(r)
ok("a blank opening balance → 200 and blocked", r.status == 200 && b.blocked === true)
ok("L1-C names the opening balance box",
   any(f -> f.code == "L1-C" && f.field == "opening_balance", b.findings))
ok("predicted and available are null, since nothing can be predicted from a blank",
   b.predicted === nothing && b.available === nothing)

# ========================================================= /api/save refusals
println("\nPOST /api/save — the refusals")
r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
b = body_of(r)
ok("first day, box unticked → 400 needsGenesis",
   r.status == 400 && b.ok === false && get(b, :needsGenesis, false) === true)
ok("and it says so in plain words", occursin("first day on record", String(b.error)))

r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, dep=900000.0, c=2270.0),
                       allowGenesis=true))
b = body_of(r)
ok("a Stop → 400 carrying findings",
   r.status == 400 && b.ok === false && findings_wellformed(b.findings))
ok("and one of them is a Stop", any(f -> f.level == 1, b.findings))
ok("nothing was written for it", !isfile(daily_ledger_path(D1)))

# ================================================================ a good save
println("\nPOST /api/save — the first day, accepted")
r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0), allowGenesis=true))
b = body_of(r)
ok("200", r.status == 200)
ok("exactly the keys app.js reads",
   keyset(b) == Set(["ok", "date", "closed", "journal", "dailyLedger", "released", "warnings"]))
ok("added to the journal, ledger written",
   String(b.journal) == "added" && String(b.dailyLedger) == "written")
ok("not a closed day", b.closed === false)
ok("the journal and the ledger are on disk",
   isfile(journal_path(2026, 4)) && isfile(daily_ledger_path(D1)))

println("\nPOST /api/save — saving the same day again")
r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0), allowGenesis=true))
b = body_of(r)
ok("200, journal replaced", r.status == 200 && String(b.journal) == "replaced")
ok("the existing ledger is left alone", String(b.dailyLedger) == "skipped")
ok("and the operator is told why", any(w -> occursin("NOT been overwritten", String(w)), b.warnings))

r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0),
                       allowGenesis=true, force=true))
b = body_of(r)
ok("with the replace box ticked → overwritten", r.status == 200 && String(b.dailyLedger) == "overwritten")

# ============================== the first day, once it is in the books
# The question "accept this opening balance as the starting point?" is asked
# once. A date that is already in the books answered it when it went in, so the
# tick box and its notice are gone and saving it again needs neither.
println("\nPOST /api/check — the first day after it has been accepted")
r = post("/api/check", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
b = body_of(r)
ok("genesis false — it is in the books already", b.genesis === false)
ok("and the first-day notice has gone with it", !any(f -> f.code == "L3-D", b.findings))
ok("but nothing claims the day before it is missing", !any(f -> f.code == "L3-A", b.findings))
ok("still in the books, still has its ledger", b.inBooks === true && b.hasDailyLedger === true)

r = get_("/api/prior?date=$(D1)"); b = body_of(r)
ok("the line under the opening balance still says it is the first day on record",
   b.genesis === true && b.hasPrior === false)

r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
b = body_of(r)
ok("re-saving it with no tick → 200, not needsGenesis",
   r.status == 200 && get(b, :needsGenesis, false) === false)
ok("the row is replaced and the ledger left as it was",
   String(b.journal) == "replaced" && String(b.dailyLedger) == "skipped")
r = post("/api/save", (date=string(D1), amounts=figures(o=1270.0, c=2270.0), force=true))
ok("and its ledger can still be regenerated, with no tick either",
   r.status == 200 && String(body_of(r).dailyLedger) == "overwritten")

# ============================================== a day with both differences
println("\nPOST /api/save — each difference needs its own reason")
diff_day = figures(o=2000.0, c=4000.0)   # opening ≠ 2270 close, and 4000 ≠ 3000 predicted

r = post("/api/save", (date=string(D2), amounts=diff_day))
b = body_of(r)
ok("no reason at all → 400 needsReason",
   r.status == 400 && get(b, :needsReason, false) === true && findings_wellformed(b.findings))

r = post("/api/save", (date=string(D2), amounts=diff_day, reason="miscounted"))
b = body_of(r)
ok("the day's reason alone is not enough",
   r.status == 400 && get(b, :needsReason, false) === true)
ok("and it asks about the opening balance",
   occursin("opening balance", String(b.error)))

r = post("/api/save", (date=string(D2), amounts=diff_day, openingReason="float left in"))
b = body_of(r)
ok("the opening reason alone is not enough",
   r.status == 400 && get(b, :needsReason, false) === true)
ok("and it asks about the day",
   occursin("doesn't balance", String(b.error)))

r = post("/api/save", (date=string(D2), amounts=diff_day,
                       reason="miscounted", openingReason="float left in"))
b = body_of(r)
ok("both reasons → saved", r.status == 200 && String(b.journal) == "added")

# ==================================================================== Off day
println("\nPOST /api/save — an Off day")
r = post("/api/save", (date=string(D3), status="closed"))
b = body_of(r)
ok("200 and marked closed", r.status == 200 && b.closed === true)
ok("no ledger is generated for it", String(b.dailyLedger) == "not applicable (closed)")
ok("and none is on disk", !isfile(daily_ledger_path(D3)))

# ================================ the two notices that name a date
# Every message on the form says a date the way a person says it. These two used
# to say 2026-04-01 while the banner beside them said 1 April 2026.
println("\nThe notices that name a date say it in words")
r = post("/api/check", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
lb = [f for f in body_of(r).findings if f.code == "L3-B"]
ok("the ledger notice: \"$(isempty(lb) ? "" : first(split(String(lb[1].message), ". ")))\"",
   length(lb) == 1 && occursin("A ledger has already been generated for 1 April 2026.",
                               String(lb[1].message)))

r = post("/api/check", (date=string(D3), status="closed"))
lc = [f for f in body_of(r).findings if f.code == "L3-C"]
ok("the closed-day notice: \"$(isempty(lc) ? "" : first(split(String(lc[1].message), ". ")))\"",
   length(lc) == 1 && occursin("3 April 2026 is recorded as closed.", String(lc[1].message)))

# ================================================================== /api/day
println("\nGET /api/day — loading a saved day back")
r = get_("/api/day?date=$(D1)"); b = body_of(r)
ok("200, day present", r.status == 200 && b.day !== nothing)
ok("the figures that were typed come back",
   abs(b.day.amounts.opening_balance - 1270.0) < 0.005 &&
   abs(b.day.amounts.closing_balance - 2270.0) < 0.005)
ok("as a trading day with no reasons",
   String(b.day.status) == "trading" && String(b.day.reason) == "" &&
   String(b.day.openingReason) == "")

r = get_("/api/day?date=$(D2)"); b = body_of(r)
ok("both reasons come back with the day",
   String(b.day.reason) == "miscounted" && String(b.day.openingReason) == "float left in")

r = get_("/api/day?date=$(D3)"); b = body_of(r)
ok("an Off day comes back closed", r.status == 200 && String(b.day.status) == "closed")

r = get_("/api/day?date=$(D4)"); b = body_of(r)
ok("a date that was never saved → day null", r.status == 200 && b.day === nothing)
ok("and it is the same shape, not a different one", keyset(b) == Set(["ok", "day"]))

r = get_("/api/day?date=not-a-date")
ok("a date that is not a date → 400", r.status == 400)

# ================================================================= /api/next
println("\nPOST /api/next — may the form move on?")
const NEXT_KEYS = Set(["ok", "saved", "changed", "date", "next", "error"])

r = post("/api/next", (date=string(D4), amounts=figures(o=9.0, c=1009.0)))
b = body_of(r)
ok("a date that was never saved → 409", r.status == 409)
ok("saved false, changed false", b.saved === false && b.changed === false)
ok("the day after is still offered", String(b.next) == string(D4 + Day(1)))
ok("and it says what to do", occursin("Save it before moving on", String(b.error)))
ok("exactly six keys", keyset(b) == NEXT_KEYS)

r = post("/api/next", (date=string(D1), amounts=figures(o=1270.0, c=2270.0)))
b = body_of(r)
ok("a day saved exactly as shown → 200", r.status == 200 && b.ok === true)
ok("saved true, changed false", b.saved === true && b.changed === false)
ok("next is the day after", String(b.next) == string(D1 + Day(1)))
ok("no error to show", b.error === nothing)
ok("exactly six keys", keyset(b) == NEXT_KEYS)

r = post("/api/next", (date=string(D1), amounts=figures(o=1270.0, c=2271.0)))
b = body_of(r)
ok("one figure changed → 409 changed", r.status == 409 && b.saved === true && b.changed === true)
ok("and it says the figures are unsaved", occursin("have not been saved", String(b.error)))

r = post("/api/next", (date=string(D2), amounts=diff_day,
                       reason="counted twice", openingReason="float left in"))
b = body_of(r)
ok("a reason changed → 409 changed", r.status == 409 && b.changed === true)

r = post("/api/next", (date=string(D2), amounts=diff_day,
                       reason="miscounted", openingReason="float left in"))
ok("the reasons as saved → 200", r.status == 200)

# The browser sends whatever is in the box. "1270.00" and 1270 are the same money.
str_figures = Dict(k => (v isa Number ? string(Float64(v)) * "0" : v)
                   for (k, v) in figures(o=1270.0, c=2270.0))
r = post("/api/next", (date=string(D1), amounts=str_figures))
b = body_of(r)
ok("the same figures typed as strings with trailing zeros → 200",
   r.status == 200 && b.changed === false)

r = post("/api/next", (date=string(D3), status="closed"))
b = body_of(r)
ok("a saved Off day, sent as an Off day → 200", r.status == 200 && b.changed === false)

r = post("/api/next", (date=string(D3), amounts=figures(o=2270.0, c=3270.0)))
b = body_of(r)
ok("the same date sent as a Work day → 409 changed", r.status == 409 && b.changed === true)

r = post("/api/next", (date=string(TODAY + Day(1)), amounts=figures(o=1.0, c=1001.0)))
ok("a date that has not happened → 400", r.status == 400)

println("\nPOST /api/next — the last day there is")
r = post("/api/save", (date=string(TODAY), amounts=figures(o=5000.0, c=6000.0)))
ok("today saves", r.status == 200)
r = post("/api/next", (date=string(TODAY), amounts=figures(o=5000.0, c=6000.0)))
b = body_of(r)
ok("200 and nothing to move on to", r.status == 200 && b.next === nothing)
ok("exactly six keys", keyset(b) == NEXT_KEYS)

# ======================================== filling a gap under a saved day
# D6 goes in while D5 is still missing, so D6's ledger waits on D5. Entering D5
# is what releases it, and the release measures D6's morning against the closing
# balance typed here — so the person typing it is told to check the two agree.
println("\nPOST /api/check — the day after this one is already on record")
r = post("/api/check", (date=string(D5), amounts=figures(o=5000.0, c=6000.0)))
ok("nothing about the day after while that day is not on record either",
   r.status == 200 && !any(f -> f.code == "L3-E", body_of(r).findings))

r = post("/api/save", (date=string(D6), amounts=figures(o=6000.0, c=7000.0)))
ok("the later day saves with its ledger held",
   r.status == 200 && String(body_of(r).dailyLedger) == "held")

r = post("/api/check", (date=string(D5), amounts=figures(o=5000.0, c=6000.0)))
b = body_of(r)
e3 = [f for f in b.findings if f.code == "L3-E"]
ok("now the reminder is raised, beside the closing balance, as a notice",
   length(e3) == 1 && String(e3[1].field) == "closing_balance" && e3[1].level == 3)
ok("titled for the Checks panel", !isempty(e3) && String(e3[1].title) == "Day after already on record")
ok("it names the day after in words, and says what to check",
   !isempty(e3) &&
   String(e3[1].message) ==
     "6 April 2026 is already on record and was waiting on this day. Check that its " *
     "opening balance matches this closing balance. If they do not agree, that day will " *
     "need an opening reason before its ledger can be made.")
ok("it does not block the day or ask for a reason",
   b.blocked === false && b.needsReason === false)

r = post("/api/check", (date=string(D6), amounts=figures(o=6000.0, c=7000.0)))
ok("not raised for a day that is in the books itself",
   !any(f -> f.code == "L3-E", body_of(r).findings))

r = post("/api/save", (date=string(D5), amounts=figures(o=5000.0, c=6000.0)))
b = body_of(r)
ok("saving the gap day releases the day that was waiting",
   r.status == 200 && string(D6) in [String(x) for x in b.released])
r = post("/api/check", (date=string(D5), amounts=figures(o=5000.0, c=6000.0)))
ok("and the reminder is gone once this day is on record too",
   !any(f -> f.code == "L3-E", body_of(r).findings))

# =================================================================== warmup()
# The whole design constraint: starting the server leaves the books untouched.
println("\nwarmup() — compiles the save path and writes nothing to the books")
scratch = Layout.warmup_file()
rm(scratch; force=true)
before = tree(Layout.ROOT)
ok("there are books to disturb", length(before) > 3)
elapsed = @elapsed warmup()
after = tree(Layout.ROOT)
ok("it ran without throwing ($(round(elapsed, digits=1)) s)", true)
ok("not one file under ROOT added, removed or resized", before == after)
ok("no warm-up scratch file left behind", !isfile(scratch))

println("\n", repeat("=", 70))
println("  PASSED $(PASS[])   FAILED $(FAIL[])")
println(repeat("=", 70))
exit(FAIL[] == 0 ? 0 : 1)
