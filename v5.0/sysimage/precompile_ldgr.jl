# =============================================================================
# precompile_ldgr.jl — the workload PackageCompiler watches while it builds the
# sysimage (see build_sysimage.jl).
#
# It is not a test. Nothing here asserts anything. Its only job is to make the
# program do, once, everything a person does in a normal day's entry, so that
# the machine code for those paths is compiled now and baked into the image
# instead of being compiled again on the clinic's machine the first time
# somebody presses Save.
#
# IT MUST NEVER TOUCH THE REAL BOOKS. LEDGER_ROOT is pointed at a throwaway
# folder on the line below, BEFORE server.jl is included, because Layout.ROOT is
# a `const` that reads the variable at include time. The folder is deleted at
# the end. Set LDGR_PRECOMPILE_ROOT to choose where that throwaway folder is
# made; otherwise it goes in the system temp folder.
#
# Every step is wrapped in try/catch. A sysimage build that dies because one
# endpoint threw would be a poor trade: a missed precompile costs a few hundred
# milliseconds once, a failed build costs twenty minutes.
# =============================================================================

using Dates

# --- the throwaway books ------------------------------------------------------
const PARENT = get(ENV, "LDGR_PRECOMPILE_ROOT", tempdir())
mkpath(PARENT)
const SCRATCH = mktempdir(PARENT; prefix = "ldgr_precompile_")
ENV["LEDGER_ROOT"]    = SCRATCH
ENV["LDGR_NO_BROWSER"] = "1"      # never open a window on a build machine
ENV["LDGR_NO_WARMUP"]  = ""       # the warm-up itself is worth precompiling

println("precompile: LEDGER_ROOT = ", SCRATCH)

# --- the program --------------------------------------------------------------
include(joinpath(@__DIR__, "..", "server.jl"))

# Belt and braces: if anything above went wrong and ROOT is not the scratch
# folder, stop rather than write somewhere real.
if basename(Layout.ROOT) == "Records"
    error("precompile: LEDGER_ROOT did not take effect — refusing to write to Records/")
end

using HTTP, JSON3

# warmup() is server.jl's own first-request rehearsal. Run it if this copy of
# server.jl has one; it exercises the same code the first Save would.
try
    if isdefined(Main, :warmup)
        println("precompile: warmup()")
        warmup()
    end
catch e
    @warn "precompile: warmup() failed" exception = e
end

# --- driving the endpoints in-process ----------------------------------------
# No port is bound. router() is the same function HTTP.serve calls, so calling
# it directly compiles exactly the code a real request would.

post(path, body) = router(HTTP.Request("POST", path,
                                       ["Content-Type" => "application/json"],
                                       JSON3.write(body)))
get_(path) = router(HTTP.Request("GET", path))

"""
The twelve category keys the form posts, as they are spelled in Config.jl.
The identity: Opening + Cash sales − Expenses − Deposit − Mr. Boyle = Closing.
"""
amounts(; o = 1270.0, s = 98400.0, e = 22400.0, dep = 75000.0, b = 0.0,
          c = o + s - e - dep - b) =
    Dict("opening_balance"      => o,
         "cash_sales"           => s,
         "POS_Scotia"           => 12500.0,
         "POS_RBL"              => 3400.0,
         "POS_U"                => 0.0,
         "doctor_fees"          => e,
         "medical_supply_costs" => 0.0,
         "miscellaneous_costs"  => 0.0,
         "taxi_fare"            => 0.0,
         "deposits"             => dep,
         "Mr_Boyle"             => b,
         "closing_balance"      => c)

step = 0
function drive(label, f)
    global step += 1
    try
        r = f()
        println("precompile: ", lpad(step, 2), "  ", rpad(label, 44), " -> ", r.status)
    catch e
        @warn "precompile: $label failed" exception = e
    end
end

# Dates well in the past: record_from_payload refuses a future date, and the
# scratch books start empty so the first one is the genesis day.
d1 = Date(2026, 4, 6)
d2 = d1 + Day(1)
d3 = d2 + Day(1)
d4 = d3 + Day(1)

# ---- reads -------------------------------------------------------------------
drive("GET  /index.html",              () -> get_("/index.html"))
drive("GET  /styles.css",              () -> get_("/styles.css"))
drive("GET  /app.js",                  () -> get_("/app.js"))
drive("GET  /api/config",              () -> handle_config())
drive("GET  /api/prior (empty books)", () -> get_("/api/prior?date=$(d1)"))
drive("GET  /api/day  (not saved)",    () -> get_("/api/day?date=$(d1)"))

# ---- checks, before anything is in the books ---------------------------------
drive("POST /api/check balanced",      () -> post("/api/check", (date = string(d1), amounts = amounts())))
drive("POST /api/check blank closing", () -> post("/api/check", (date = string(d1),
                                                                 amounts = amounts(c = ""))))
drive("POST /api/check off day",       () -> post("/api/check", (date = string(d1), status = "closed")))
drive("POST /api/next  before save",   () -> post("/api/next", (date = string(d1), amounts = amounts())))

# ---- the first day on record -------------------------------------------------
drive("POST /api/save  genesis",       () -> post("/api/save", (date = string(d1),
                                                                amounts = amounts(),
                                                                allowGenesis = true)))
drive("POST /api/next  after save",    () -> post("/api/next", (date = string(d1), amounts = amounts())))
drive("GET  /api/day   (saved)",       () -> get_("/api/day?date=$(d1)"))
drive("GET  /api/prior (has prior)",   () -> get_("/api/prior?date=$(d2)"))

# ---- an ordinary second day --------------------------------------------------
a2 = amounts(o = amounts()["closing_balance"])
drive("POST /api/check day 2",         () -> post("/api/check", (date = string(d2), amounts = a2)))
drive("POST /api/save  day 2",         () -> post("/api/save", (date = string(d2), amounts = a2)))

# ---- a day with BOTH differences, each with its own reason -------------------
# The opening does not match day 2's close (L2-B) and the drawer count does not
# match the prediction (L2-A). Both reason boxes are filled, so it saves.
a3 = amounts(o = 999.0, c = 4000.0)
drive("POST /api/check both diffs",    () -> post("/api/check", (date = string(d3), amounts = a3,
                                                                 reason = "Short at close",
                                                                 openingReason = "Float topped up")))
drive("POST /api/save  refused, silent", () -> post("/api/save", (date = string(d3), amounts = a3)))
drive("POST /api/save  both reasons",  () -> post("/api/save", (date = string(d3), amounts = a3,
                                                                reason = "Short at close",
                                                                openingReason = "Float topped up")))

# ---- an Off day --------------------------------------------------------------
drive("POST /api/save  off day",       () -> post("/api/save", (date = string(d4), status = "closed")))

# ---- re-saving a day that is already in the books ----------------------------
drive("POST /api/save  re-save, no force", () -> post("/api/save", (date = string(d2), amounts = a2)))
drive("POST /api/save  re-save, force",    () -> post("/api/save", (date = string(d2), amounts = a2,
                                                                    force = true)))

# ---- refusals, so their paths are compiled too -------------------------------
drive("POST /api/check bad category",  () -> post("/api/check", (date = string(d2),
                                                                 amounts = Dict("nonsense" => 1))))
drive("POST /api/check bad date",      () -> post("/api/check", (date = "not-a-date",)))
drive("GET  /nothing-here",            () -> get_("/nothing-here.html"))

# --- the same thing again, over a real socket --------------------------------
# Everything above goes through `router` in-process. That leaves out HTTP.jl's
# ENTIRE SERVER SIDE — accepting the connection, parsing the request off the
# wire, streaming the reply back — which is a large body of code and compiles
# on whichever request arrives first. Measured on the integrated tree: with the
# packages already in a system image and warmup() run, HTTP.serve! still took
# 2 s and the first request over a real socket took 10.9 s, in front of a form
# showing nothing. So the whole round trip is driven here too.
#
# listenany picks a free high port, so no fixed port is taken and two builds on
# one machine cannot collide. Nothing else can reach it: it binds 127.0.0.1 and
# is closed in a `finally`.

using Sockets

# Dates BEFORE the days saved above, so nothing is on record before the first
# one and it is a genuine genesis save.
s1 = Date(2026, 3, 2)
s2 = s1 + Day(1)
sa1 = amounts()
sa2 = amounts(o = sa1["closing_balance"])

println("precompile: -- over a real socket --")
try
    port, tcp = Sockets.listenany(Sockets.ip"127.0.0.1", 49152)
    srv = HTTP.serve!(router, "127.0.0.1", Int(port); server = tcp)
    try
        url = "http://127.0.0.1:$port"
        hdr = ["Content-Type" => "application/json"]
        # status_exception=false throughout: several of these answer 400 or 409
        # by design, and a refusal is a code path worth compiling too.
        sget(p) = HTTP.get(url * p; status_exception = false)
        spost(p, b) = HTTP.post(url * p, hdr, JSON3.write(b); status_exception = false)

        drive("SOCK GET  /",                    () -> sget("/"))
        drive("SOCK GET  /api/config",          () -> sget("/api/config"))
        drive("SOCK GET  /api/prior",           () -> sget("/api/prior?date=$(s1)"))
        drive("SOCK POST /api/check balanced",  () -> spost("/api/check", (date = string(s1), amounts = sa1)))
        drive("SOCK POST /api/check difference", () -> spost("/api/check",
                  (date = string(s1), amounts = amounts(o = 999.0, c = 4000.0),
                   reason = "Short at close", openingReason = "Float topped up")))
        drive("SOCK POST /api/next  before save", () -> spost("/api/next", (date = string(s1), amounts = sa1)))
        drive("SOCK POST /api/save  genesis",   () -> spost("/api/save",
                  (date = string(s1), amounts = sa1, allowGenesis = true)))
        drive("SOCK POST /api/next  after save", () -> spost("/api/next", (date = string(s1), amounts = sa1)))
        drive("SOCK POST /api/save  day 2",     () -> spost("/api/save", (date = string(s2), amounts = sa2)))
        drive("SOCK GET  /nothing-here",        () -> sget("/nothing-here.html"))
    finally
        close(srv)
    end
catch e
    @warn "precompile: the socket round trip failed" exception = e
end

# --- tidy up ------------------------------------------------------------------
println("precompile: removing ", SCRATCH)
try
    rm(SCRATCH; recursive = true, force = true)
catch e
    @warn "precompile: could not remove the scratch folder" exception = e
end
println("precompile: done (", step, " steps)")
