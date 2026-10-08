# =============================================================================
# test_notify.jl — the paper trail and the one daily report.
#
# Run:  LEDGER_ROOT=/tmp/ldgr_notify julia --startup-file=no test_notify.jl
#
# Writes to LEDGER_ROOT only, and CLEARS IT FIRST so the run is repeatable.
# It refuses to start if LEDGER_ROOT is unset or names a folder called
# "Records". Never point this at the real books.
#
# NOTHING IS EVER SENT, AND NOTHING LEAVES THIS MACHINE. Two stand-ins make that
# true:
#
#   * A FAKE MAILER. `Notify.MAILER[]` is how a report leaves the machine — a
#     NamedTuple of two functions, `send` and `cancel`. Here it is a fake that
#     writes down every email it is handed (with its idempotency key) and every
#     cancel, answers a repeated key with the id it gave the first time (as
#     Resend does), and can be told to fail the way Resend fails: a `:temporary`
#     Resend.Failure (no internet) or a `:settings` one (a wrong key or address).
#     It is the only reason every branch of `Notify.tick` can be tested at all.
#
#   * A LOCAL STUB SERVER. Resend.jl — the one file that speaks HTTP — is tested
#     against a small server this script runs on 127.0.0.1, on a spare port.
#     `Resend.API_BASE[]` is pointed at it on the line after Resend.jl is loaded,
#     and every call into Resend goes through `local_only()`, which stops the run
#     dead if that address is anything but 127.0.0.1. No test contacts Resend or
#     the internet.
#
# The settings file is written INSIDE the scratch root, with a made-up key, and
# pointed at with LDGR_NOTIFY_CONFIG before anything is loaded, so an installed
# notify.toml is never read and never touched. LDGR_NO_DIGEST=1 keeps the
# scheduler's timer from ever starting.
#
# TIME IS PASSED IN, NOT WAITED FOR. `tick(at = ...)` takes the clock as an
# argument. The scheduling groups (16 on) work in made-up stretches of 2031 and
# 2032: their change-log rows are written there directly, with the moment of
# each save given, and the marker is set just before the stretch, so the real
# rows written by groups 2-14 fall outside every window. Those groups therefore
# give the same answer whatever time of day the test is run. The two places that
# must use the real clock — a save's poke (groups 29 and 41) — work relative to
# it, with a send time hours away from now.
#
# Groups 30 to 43 each check one fix made after the review of 28 September 2026
# (F1-F17 in its numbering; F8 is checked in group 27). Groups 44 to 48 cover
# fixes from the later review rounds (a ledger released by an edit, damaged
# lines in the change log, an unconfirmed hand-over, a cut before a quote and a
# cut heading, and the "may repeat" note with the terminal warnings). Group 49
# checks that a day's session ends at midnight or at the send time, whichever
# comes first, and group 50 checks the key. Groups 51 to 61 are about the HTML
# body of the report (EmailHtml.jl): that it shows the same facts as the text,
# safely, attention first, and that it travels in the email, the idempotency
# key and the pending table; the last of them checks the key once more.
#
# WHAT MATTERS HERE IS THE POLICY, not the plumbing. Three things are being
# proved. First, that every write to the books leaves a row behind — whether or
# not email is configured — so nothing that happens to a day can be quietly
# undone. Second, that the one report the owner receives says, in plain words
# and without a single warning code, what was entered, what was changed after
# the fact, which gaps were filled and which ledgers are still waiting — and
# never says "nothing happened" when the change log simply could not be read.
# Third, that the report handed to Resend in advance is always the current one:
# replaced after every save, corrected when a save came too late, sent late when
# nothing covered a stretch, and never duplicated by a retry.
# =============================================================================

using Dates, TOML

# ---------------------------------------------------------------- safety first
# Checked BEFORE main.jl is loaded, because Layout.ROOT is fixed at load time
# and because this test empties the folder it is given.
const SCRATCH = get(ENV, "LEDGER_ROOT", "")
isempty(SCRATCH) &&
    error("Set LEDGER_ROOT to a scratch folder before running this test. " *
          "Without it everything is written under v4.0/Records, which holds the real books.")
basename(rstrip(SCRATCH, ['\\', '/'])) == "Records" &&
    error("LEDGER_ROOT names a folder called \"Records\". Point it at a scratch folder.")

rm(SCRATCH; recursive = true, force = true)
mkpath(SCRATCH)

# The email settings live inside the scratch root, so the installed notify.toml
# (and the dead password in it) is never read by a test.
const CONFIG = joinpath(SCRATCH, "notify-test.toml")
ENV["LDGR_NOTIFY_CONFIG"] = CONFIG          # absent until it is written, below
ENV["LDGR_NO_DIGEST"]     = "1"             # no timer, ever, from a test

include("main.jl")

basename(rstrip(Layout.ROOT, ['\\', '/'])) == "Records" &&
    error("Layout.ROOT resolved to a Records folder. Refusing to run.")

# ------------------------------------------------ Resend.jl, pointed at a stub
# Loaded after main.jl, as server.jl loads it. The stub's port is picked FIRST,
# so that API_BASE can be pointed at it on the very next line after the include,
# before anything could possibly call out. The OS picks a free loopback port;
# the socket is handed back and HTTP.jl binds the port itself, exactly as the
# server's warm-up does.
import HTTP, JSON3, Sockets, Logging

const STUB_PORT = let
    # A random place to start looking, so two copies of this test run side by side
    # do not both land on the first free port in the moment before HTTP.jl binds it.
    port, tcp = Sockets.listenany(Sockets.ip"127.0.0.1", rand(49152:64000))
    close(tcp)
    Int(port)
end

include("Resend.jl")
Resend.API_BASE[] = "http://127.0.0.1:$(STUB_PORT)"
const DEFAULT_TIMEOUTS = Resend.TIMEOUTS[]      # checked in group 25, before it is shortened

"""
Refuse to go on unless Resend is pointed at 127.0.0.1. Called before every call
that could reach Resend.jl, so no edit to this file can ever send for real.
"""
function local_only()
    b = Resend.API_BASE[]
    # https is allowed only so that group 43 can reach its own self-signed stub —
    # still on 127.0.0.1, still on this machine.
    occursin(r"^https?://127\.0\.0\.1:\d+$", b) ||
        error("Resend.API_BASE[] is \"$(b)\", not a stub on 127.0.0.1. Refusing to go on: " *
              "no test may contact Resend or the internet.")
    return nothing
end
local_only()

# The stub. `:auto` answers like Resend: an id for each new email, and an
# acknowledgement for each cancel. A tuple `(status, body, delay)` answers every
# request with that status and body, after `delay` seconds.
const STUB_HITS = Any[]
const STUB_MODE = Ref{Any}(:auto)
const STUB_IDS  = Ref(0)

function stub_handler(req::HTTP.Request)
    hit = (method  = String(req.method),
           target  = String(req.target),
           headers = Dict{String,String}(lowercase(String(k)) => String(v) for (k, v) in req.headers),
           body    = String(copy(req.body)))
    push!(STUB_HITS, hit)
    json = ["Content-Type" => "application/json"]
    mode = STUB_MODE[]
    if mode === :auto
        if hit.method == "POST" && hit.target == "/emails"
            STUB_IDS[] += 1
            return HTTP.Response(200, json, "{\"id\":\"stub-$(STUB_IDS[])\"}")
        end
        m = match(r"^/emails/([^/]+)/cancel$", hit.target)
        if hit.method == "POST" && m !== nothing
            return HTTP.Response(200, json, "{\"object\":\"email\",\"id\":\"$(m[1])\"}")
        end
        return HTTP.Response(404, json,
            "{\"statusCode\":404,\"name\":\"not_found\",\"message\":\"The requested endpoint does not exist.\"}")
    end
    status, body, delay = mode
    delay > 0 && sleep(delay)
    return HTTP.Response(status, json, body)
end

# HTTP.jl's server side is chatty about dropped connections (the slow-reply test
# drops one on purpose); its tasks inherit this silent logger.
const STUB = Logging.with_logger(Logging.NullLogger()) do
    HTTP.serve!(stub_handler, "127.0.0.1", STUB_PORT)
end

# --------------------------------------------------------------------- harness
const PASS = Ref(0); const FAIL = Ref(0)

function ok(label, cond)
    cond === true ? (PASS[] += 1; println("  PASS  $label")) :
                    (FAIL[] += 1; println("  FAIL  $label"))
end

function day(d; o = 1000.0, s = 0.0, e = 0.0, dep = 0.0, b = 0.0, c = 1000.0,
             reason = "", opening_reason = "")
    a = blank_amounts()
    a[:opening_balance] = o; a[:closing_balance] = c
    a[:cash_sales] = s; a[:doctor_fees] = e; a[:deposits] = dep; a[:Mr_Boyle] = b
    DayRecord(d, a, STATUS_TRADING, reason, opening_reason)
end

"""
One save, exactly as the two front doors do it: read what the books said before
this write, write the day, then append the change-log row from what is in hand.
`before` is read first because `upsert_day!` replaces a row in place — after
`process_day` the old figures are gone.
"""
function save(rec; force = false, genesis = false)
    d = rec.date
    before = (in_books      = Chain.on_record(d),
              next_in_books = Chain.on_record(d + Day(1)),
              ledger_exists = isfile(daily_ledger_path(d)))
    previous = before.in_books ? Chain.saved_record(d) : nothing
    out = process_day(rec; echo = false, force = force, allow_genesis = genesis)
    # `send_at = nothing`: these saves run on the real clock, so only midnight
    # ends a day's session here and the groups pass at any hour. The send time
    # as the other end of a session is checked at fixed times in group 49.
    Changes.after_save(out; rec = rec, previous = previous, before = before, send_at = nothing)
    return (out = out, rows = Changes.rows_between(nothing, now()))
end

# --- reading the log back ---------------------------------------------------
logrows() = Changes.rows_between(nothing, now())
nrows()   = length(logrows())
daystr(r) = first(string(r.day), 10)
rows_for(d::Date) = filter(r -> daystr(r) == string(d), logrows())
function last_row(d::Date)
    rs = rows_for(d)
    isempty(rs) ? nothing : rs[end]
end
text(x) = x === nothing || x === missing ? "" : strip(string(x))
istrue(x)  = x === true  || lowercase(text(x)) in ("true", "yes", "1")
isfalse(x) = x === false || lowercase(text(x)) in ("false", "no", "0", "")
function num(x)
    x isa Real && return Float64(x)
    v = tryparse(Float64, text(x))
    v === nothing ? 0.0 : v
end
near(a, b) = abs(num(a) - b) < 0.005

logtext() = isfile(Layout.change_log_path()) ? read(Layout.change_log_path(), String) : ""
loglines() = [String(rstrip(l, '\r')) for l in split(logtext(), '\n') if !isempty(strip(l))]

"""
Move one day's change-log rows back in time. `Day(1)` makes the next save of
that day look like an edit on a later calendar date; `Hour(2)` leaves it on the
same date but puts it outside a report window that starts an hour ago. This is
the only way to test the session rule inside one run: the rule is "the date it
was first saved", and a test cannot wait until tomorrow.
"""
function backdate!(d::Date, back::Period = Day(1))
    p = Layout.change_log_path()
    lines = [String(rstrip(l, '\r')) for l in split(read(p, String), '\n')]
    stamp = Dates.format(now() - back, "yyyy-mm-dd HH:MM:SS")
    moved = 0
    for i in eachindex(lines)
        isempty(strip(lines[i])) && continue
        parts = split(lines[i], ',')
        length(parts) == length(Changes.COLUMNS) || continue   # never touch a quoted row
        strip(parts[4]) == string(d) || continue
        parts[1] = stamp
        lines[i] = join(parts, ',')
        moved += 1
    end
    write(p, join(lines, '\n'))
    return moved
end

# --- reading the report back ------------------------------------------------
const HEADINGS = ["DAYS ENTERED",
                  "CHANGES TO DAYS ALREADY SAVED",
                  "GAPS FILLED, AND THE LEDGERS THEY RELEASED",
                  "LEDGERS STILL WAITING"]

has_section(body, title) = any(strip(l) == title for l in split(body, '\n'))

# The sentence rows_checked writes for one unreadable row. `row` counts data
# rows from 1; the owner is told the line number, counting the heading as 1.
line_problem(row) = "Line $(row + 1) of Change Log.csv (counting the heading as line 1) could not " *
                    "be read and was left out."
line_prefix(row) = "Line $(row + 1) of Change Log.csv"

"The lines under one heading, up to the next heading."
function section(body::AbstractString, title::AbstractString)
    out = String[]; inside = false
    for line in split(body, '\n')
        s = strip(line)
        if s in HEADINGS
            inside = (s == title)
            continue
        end
        inside && push!(out, String(line))
    end
    return join(out, "\n")
end

"One day's block inside a section: its first line and the lines under it, up to
the blank line that ends it."
function block(sec::AbstractString, head::AbstractString)
    out = String[]; inside = false
    for line in split(sec, '\n')
        if !inside && startswith(line, head)
            inside = true
            push!(out, String(line))
        elseif inside
            isempty(strip(line)) && break
            push!(out, String(line))
        end
    end
    return join(out, "\n")
end

"All the whitespace in a text as single spaces, so a sentence can be found
however the report wrapped it."
flat(s::AbstractString) = join(split(s), " ")

"The first paragraph under the report's heading block — where the notes go."
function first_para(body::AbstractString)
    parts = split(replace(body, "\r\n" => "\n"), "\n\n")
    return length(parts) >= 2 ? flat(parts[2]) : ""
end

"The very first paragraph of a report — above the heading, where a report that
could not read the change log says so."
lead_para(body::AbstractString) = flat(first(split(replace(body, "\r\n" => "\n"), "\n\n")))

"Does `a` appear in `text`, and before `b`?"
function before(text::AbstractString, a::AbstractString, b::AbstractString)
    x = findfirst(a, text); y = findfirst(b, text)
    return x !== nothing && y !== nothing && first(x) < first(y)
end

count_of(needle::AbstractString, hay::AbstractString) = length(findall(needle, hay))

digest(from = nothing, to = now()) = Notify.build_digest(from, to)

# A day that was both entered and changed inside one window is told once, as a
# day entered, with its final figures — that is the point of the same-date rule.
# To read the CHANGES section a window has to start AFTER the day went in, which
# is what these two give: "since midnight" for a day saved yesterday, and "the
# last hour" for a day saved earlier today.
since_midnight() = DateTime(Dates.today())
since_an_hour_ago() = now() - Hour(1)

auditlog() = isfile(Layout.audit_log_path()) ? read(Layout.audit_log_path(), String) : ""

# --- the fake mailer --------------------------------------------------------
# Stands in for Resend in `Notify.MAILER[]`. It records what it accepted, in
# order, and can be made to fail. Like Resend, a repeated idempotency key gets
# back the id of the email it made the first time rather than a second email.
const CREATES      = Any[]      # (key, email, idem, id), each email accepted
const ALL_CREATES  = Any[]      # the same, never emptied, for the final key check
const CANCELS      = Any[]      # (key, id), each cancel accepted
const EVENTS       = String[]   # "create:<id>" / "cancel:<id>", in the order they happened
const SEND_TRIES   = Ref(0)
const CANCEL_TRIES = Ref(0)
const SEND_FAIL    = Ref{Any}(nothing)   # an exception for `send` to throw, or nothing
const CANCEL_FAIL  = Ref{Any}(nothing)   # the same for `cancel`
const LOSE_REPLY   = Ref(false)          # accept the next email, then lose the answer
const IDS_BY_KEY   = Dict{String,String}()
const FAKE_IDS     = Ref(0)

function fake_send(key, email, idem)
    SEND_TRIES[] += 1
    SEND_FAIL[] === nothing || throw(SEND_FAIL[])
    k = String(idem)
    id = get!(IDS_BY_KEY, k) do
        FAKE_IDS[] += 1
        "fake-$(FAKE_IDS[])"
    end
    rec = (key = String(key), email = deepcopy(Dict{String,Any}(email)), idem = k, id = id)
    push!(CREATES, rec); push!(ALL_CREATES, rec)
    push!(EVENTS, "create:" * id)
    if LOSE_REPLY[]
        LOSE_REPLY[] = false
        throw(Resend.Failure(:temporary, "The internet or Resend could not be reached: the " *
                                         "connection was cut off. (test: the reply was lost)"))
    end
    return id
end

function fake_cancel(key, id)
    CANCEL_TRIES[] += 1
    CANCEL_FAIL[] === nothing || throw(CANCEL_FAIL[])
    push!(CANCELS, (key = String(key), id = String(id)))
    push!(EVENTS, "cancel:" * String(id))
    return nothing
end

const FAKE = (send = fake_send, cancel = fake_cancel)

const NONE = (key = "", email = Dict{String,Any}(), idem = "", id = "")
"The email accepted last (`created()`), or `i` before that (`created(-1)`); never throws."
created(i::Int = 0) = (n = length(CREATES) + i; 1 <= n <= length(CREATES) ? CREATES[n] : NONE)
subject_of(c) = String(get(c.email, "subject", ""))
body_of(c)    = String(get(c.email, "text", ""))
sched_of(c)   = get(c.email, "scheduled_at", nothing)
"`ldgr-<cutoff>-g<generation>-<hash>`, taken apart, or nothing."
keyparts(k::AbstractString) = match(r"^ldgr-(\d{12})-g(\d+)-([0-9a-f]{16})$", k)
keygen(k)  = (m = keyparts(k); m === nothing ? -1 : parse(Int, m[2]))
keyhash(k) = (m = keyparts(k); m === nothing ? "" : String(m[3]))

"Start a scheduling scenario from nothing: no state file, the marker at
`marker` (or none), no pauses, the fake mailer installed and emptied."
function fresh_schedule!(marker)
    rm(Layout.scheduled_state_path(); force = true)
    rm(Layout.digest_marker_path(); force = true)
    marker === nothing || Notify.mark_reported!(marker)
    Notify.BACKOFF[] = nothing
    Notify.CANCEL_BACKOFF[] = nothing
    Notify.LAST_TROUBLE[] = ("", DateTime(0))
    Notify.LAST_CANCEL_TROUBLE[] = ("", DateTime(0))
    SEND_FAIL[] = nothing; CANCEL_FAIL[] = nothing; LOSE_REPLY[] = false
    empty!(CREATES); empty!(CANCELS); empty!(EVENTS); empty!(IDS_BY_KEY)
    SEND_TRIES[] = 0; CANCEL_TRIES[] = 0
    Notify.MAILER[] = FAKE
    return nothing
end

"One tick at a given moment; a tick that throws is reported, not fatal."
function tick_at(t::DateTime; force = false, poked = false)
    try
        return Notify.tick(at = t, force = force, poked = poked)
    catch e
        println("      -> tick threw: ", sprint(showerror, e))
        return Symbol[:threw]
    end
end

"""
One change-log row written at a given moment, as a save would have written it:
a balanced trading day. This is how the scheduling groups put saves where they
want them in time — `after_save` stamps a row with the real clock.
"""
function logged!(when::DateTime, d::Date; who = "tester")
    Changes._append!(Changes.Row[Changes.Row((when, who, "saved", d, "trading", "added", "written",
                                              0.0, 0.0, "", "", NaN, NaN, "",
                                              false, false, false, false, nothing))])
    return nothing
end

statefile() = Layout.scheduled_state_path()
"`scheduled report.toml`, read back as a dictionary (empty when it is absent)."
state() = isfile(statefile()) ? TOML.parsefile(statefile()) : Dict{String,Any}()
leftovers() = [String(c["id"]) for c in get(state(), "cancel", Any[])]
stamp(t::DateTime) = Dates.format(t, "yyyy-mm-dd HH:MM:SS")

"Rewrite notify.toml and wait until its modified time has visibly changed."
function bump_config!(content::AbstractString = read(CONFIG, String))
    before = mtime(CONFIG)
    for _ in 1:50
        write(CONFIG, content)
        mtime(CONFIG) != before && return true
        sleep(0.1)
    end
    return false
end

"Every call into Resend.jl goes through here: the address is checked first, and a
thrown error comes back as a value so one bad answer cannot end the run."
function via_stub(f)
    local_only()
    try
        return f()
    catch e
        return e
    end
end
isfailure(e, kind::Symbol) = e isa Resend.Failure && e.kind === kind

const PASSWORD = "sw0rdf1sh-app-password"
const KEY = "re_FAKE_ldgr_test_key_0123456789abcdefXYZ"    # made up; never a real key
const WHO = get(ENV, "USERNAME", get(ENV, "USER", ""))
const FROM = "LDGR Daily Report <reports@example.invalid>"   # a verified domain, in real life

"The notify.toml the scheduling groups use."
const SETTINGS = """
to = "owner@example.invalid"
api_key = "$(KEY)"
from = "$(FROM)"
subject_prefix = "ldgr: "
send_at = "17:30"
"""

println("\n", repeat("=", 74))
println("  LDGR v4.0 — THE CHANGE LOG AND THE ONE DAILY REPORT")
println("  ROOT: $(Layout.ROOT)")
println("  Resend stub: $(Resend.API_BASE[])")
println(repeat("=", 74))

# =============================================================================
# 1. Off by default
# =============================================================================
println("\n1. With no notify.toml at all")

ok("email is off", Notify.enabled() === false)
ok("and there are no settings to read", Notify.settings() === nothing)
ok("a tick does nothing and says so", Notify.tick() == [:off])
ok("the start-up line says why", Notify.banner() == "off (no notify.toml)")

println("\n   The old Gmail settings, with no Resend key")
write(CONFIG, """
to = "owner@example.invalid"
from = "clinic@example.invalid"
smtp = "smtps://smtp.example.invalid:465"
user = "clinic@example.invalid"
password = "$(PASSWORD)"
""")
Notify.MAILER[] = FAKE
ok("an old SMTP-style notify.toml leaves email off", Notify.enabled() === false)
ok("and the start-up line says it has no Resend api_key",
   Notify.banner() == "off (notify.toml has no Resend api_key)")
ok("a tick does nothing with it, even with a mailer in place", Notify.tick() == [:off])
ok("and nothing was handed to the mailer", SEND_TRIES[] == 0 && CANCEL_TRIES[] == 0)

println("\n   A settings file that cannot be read, and one with no address")
write(CONFIG, "to = \"owner@example.invalid\nthis line is broken = = =\n")
ok("a notify.toml that cannot be parsed leaves email off, and says so",
   Notify.settings() === nothing && Notify.banner() == "off (notify.toml could not be read)")
ok("a tick does nothing with it", Notify.tick() == [:off])
write(CONFIG, "api_key = \"$(KEY)\"\n")
ok("a key with no `to` address leaves email off, and says so",
   Notify.settings() === nothing && Notify.banner() == "off (notify.toml has no to address)")
ok("and that line does not show the key", !occursin(KEY, Notify.banner()))
write(CONFIG, "to = \"owner@example.invalid\"\napi_key = \"$(KEY)\"\n")
ok("a key and an address but no `from` leaves email off, and says so: there is no fallback sender",
   Notify.settings() === nothing && Notify.banner() == "off (notify.toml has no from address)")
ok("a tick does nothing with it either", Notify.tick() == [:off])
ok("nothing was handed to the mailer", SEND_TRIES[] == 0 && CANCEL_TRIES[] == 0)
Notify.MAILER[] = nothing
rm(CONFIG; force = true)
ok("the test settings file is gone again", !isfile(CONFIG) && Notify.banner() == "off (no notify.toml)")
ok("no Notifications folder was created", !isdir(Layout.notifications_dir()))

# =============================================================================
# 2. The log is written whether or not email is configured
# =============================================================================
println("\n2. The change log is kept even with email off")

g = save(day(Date(2026, 2, 2); o = 1000.0, c = 1000.0); genesis = true)
ok("the first day saves", g.out.ok)
ok("a change log now exists", isfile(Layout.change_log_path()))
ok("its name is Change Log.csv", basename(Layout.change_log_path()) == "Change Log.csv")
ok("the columns are the nineteen agreed", length(Changes.COLUMNS) == 19)
ok("and they are named as agreed",
   Changes.COLUMNS == ["when", "who", "what", "day", "day kind", "journal", "ledger",
                       "day difference", "night difference", "reason", "night reason",
                       "was day difference", "was night difference", "changed",
                       "cross day edit", "pending day", "now balances", "filled a gap",
                       "released by"])
hdr = [String(strip(x, ['"', ' '])) for x in split(loglines()[1], ',')]
ok("the file's header row is those columns", hdr == Changes.COLUMNS)
ok("one save, one row", nrows() == 1)

save(day(Date(2026, 2, 3); o = 1000.0, s = 500.0, e = 200.0, c = 1300.0))
ok("a second save appends rather than starting again", nrows() == 2)
ok("and the header is written once, not twice",
   count(l -> startswith(l, "when,") || startswith(l, "\"when\","), loglines()) == 1)
ok("still no Notifications folder — the log is not the email",
   !isdir(Layout.notifications_dir()))

# =============================================================================
# 3. What a new day's row says
# =============================================================================
println("\n3. A day entered for the first time")

r = last_row(Date(2026, 2, 3))
ok("there is a row for it", r !== nothing)
ok("it says the day was saved", text(r.what) == "saved")
ok("the journal row was added, not replaced", text(r.journal) == "added")
ok("the ledger was written", text(r.ledger) == "written")
ok("it was a trading day", text(r.kind) == "trading")
ok("it names who typed it", !isempty(text(r.who)) && text(r.who) == WHO)
ok("the day balanced", near(r.day_diff, 0.0) && near(r.night_diff, 0.0))
ok("no reason was needed", isempty(text(r.reason)) && isempty(text(r.night_reason)))
ok("none of the four flags are raised",
   isfalse(r.cross_day_edit) && isfalse(r.pending_day) &&
   isfalse(r.now_balances) && isfalse(r.filled_a_gap))
ok("nothing released it", isempty(text(r.released_by)))
ok("and it was first seen today", Changes.first_seen(Date(2026, 2, 3)) == Dates.today())
ok("a day that was never saved has no first sighting",
   Changes.first_seen(Date(2026, 2, 28)) === nothing)

# ------------------------------------------------------------ email switched on
println("\n   Turning the email on")
write(CONFIG, SETTINGS)
Notify.MAILER[] = FAKE
ok("email is on", Notify.enabled() === true)
ok("and the owner is named for the startup line",
   Notify.recipient() == "owner@example.invalid")
ok("the key is read from notify.toml", Notify.settings().api_key == KEY)
ok("the report comes from the address in notify.toml", Notify.settings().from == FROM)
bn = Notify.banner()
ok("the start-up line names the owner, the time and Resend",
   startswith(bn, "on -> owner@example.invalid  (daily report at 17:30, sent by Resend; " *
                  "last complete report: none yet)"))
ok("and says the timer is off in a test run", occursin("[not scheduled: LDGR_NO_DIGEST=1]", bn))
ok("the start-up line never shows the key", !occursin(KEY, bn))
ok("THE API KEY IS NOT IN THE AUDIT LOG", !occursin(KEY, auditlog()))

# =============================================================================
# 4. A correction on the same day it was typed is a free correction
# =============================================================================
println("\n4. The same day saved again, the same calendar date")

save(day(Date(2026, 2, 3); o = 1000.0, s = 600.0, e = 300.0, c = 1300.0))
r = last_row(Date(2026, 2, 3))
ok("the row calls it an edit", text(r.what) == "edited")
ok("the journal row was replaced", text(r.journal) == "replaced")
ok("it is not a later-date edit", isfalse(r.cross_day_edit))
ok("and it is not a pending day", isfalse(r.pending_day))
ok("the log still kept it", length(rows_for(Date(2026, 2, 3))) == 2)

subj, body = digest()
ok("the report says nothing about it",
   !has_section(body, "CHANGES TO DAYS ALREADY SAVED"))
ok("but the day is still listed as entered",
   occursin("3 February 2026", section(body, "DAYS ENTERED")))
ok("and it is shown as balanced",
   occursin("3 February 2026 — balanced.", body))

# =============================================================================
# 5. A correction on a later date is reported
# =============================================================================
println("\n5. A day changed after the date it was typed")

save(day(Date(2026, 2, 4); o = 1300.0, c = 1300.0))
ok("the day goes in", Chain.on_record(Date(2026, 2, 4)))
ok("its row can be moved back a day", backdate!(Date(2026, 2, 4)) == 1)
ok("so the books think it was first saved yesterday",
   Changes.first_seen(Date(2026, 2, 4)) == Dates.today() - Day(1))

save(day(Date(2026, 2, 4); o = 1300.0, s = 500.0, c = 1800.0))
r = last_row(Date(2026, 2, 4))
ok("the row calls it an edit", text(r.what) == "edited")
ok("and marks it as a later-date edit", istrue(r.cross_day_edit))
ok("it says what moved", occursin("->", text(r.changed)))
ok("naming the box", occursin("closing balance", lowercase(text(r.changed))))
ok("with the figure before and the figure after",
   occursin("\$1,300.00", text(r.changed)) && occursin("\$1,800.00", text(r.changed)))

subj, body = digest(since_midnight())
sec = section(body, "CHANGES TO DAYS ALREADY SAVED")
ok("the report has a section for changes", has_section(body, "CHANGES TO DAYS ALREADY SAVED"))
ok("it names the day in words", occursin("4 February 2026", sec))
ok("it shows before and after", occursin("\$1,300.00", sec) && occursin("\$1,800.00", sec))
ok("it names who changed it", isempty(WHO) || occursin(WHO, sec))
ok("and when the day was first saved",
   occursin(Checks.spoken_date(Dates.today() - Day(1)), sec))

# =============================================================================
# 6. A day whose ledger is still waiting is never a free correction
# =============================================================================
println("\n6. A day saved into a gap, then corrected the same date")

held = save(day(Date(2026, 2, 8); o = 2500.0, c = 2500.0,
                opening_reason = "Sunday takings banked on Monday"))
ok("its ledger is held — the day before it is missing",
   held.out.daily_ledger == "held")
ok("the log says the ledger was held", text(last_row(Date(2026, 2, 8)).ledger) == "held")
ok("and the ledger is on the waiting list",
   Chain.waiting_ledgers() == [Date(2026, 2, 8)])

# Captured now, asserted in group 10: the waiting list has to be read while
# something is still waiting.
const WAITING_WHILE_HELD = digest()[2]

# Earlier today: two hours ago, or midnight if that is sooner, so that the run
# passes between 00:00 and 02:00 too.
backdate!(Date(2026, 2, 8), min(Hour(2), now() - floor(now(), Day)))

save(day(Date(2026, 2, 8); o = 2500.0, s = 300.0, e = 300.0, c = 2500.0,
         opening_reason = "Sunday takings banked on Monday"))
r = last_row(Date(2026, 2, 8))
ok("the correction is an edit", text(r.what) == "edited")
ok("made on the same date", isfalse(r.cross_day_edit))
ok("but it is flagged as a pending day", istrue(r.pending_day))

subj, body = digest(since_an_hour_ago())
sec = section(body, "CHANGES TO DAYS ALREADY SAVED")
ok("so the report names it after all", occursin("8 February 2026", sec))
ok("and says why it could not wait",
   occursin("waiting on the day before it", sec))

# =============================================================================
# 7. A day put right
# =============================================================================
println("\n7. A day that did not balance, corrected until it did")

save(day(Date(2026, 2, 5); o = 1800.0, s = 500.0, e = 200.0, c = 1700.0,
         reason = "Could not locate"))
r = last_row(Date(2026, 2, 5))
ok("the shortage is on the row", near(r.day_diff, -400.0))
ok("with the typed reason", text(r.reason) == "Could not locate")
backdate!(Date(2026, 2, 5))

save(day(Date(2026, 2, 5); o = 1800.0, s = 500.0, e = 200.0, c = 2100.0))
r = last_row(Date(2026, 2, 5))
ok("the correction is an edit", text(r.what) == "edited")
ok("the day balances now", near(r.day_diff, 0.0))
ok("and the row says so", istrue(r.now_balances))
ok("the difference it used to carry is kept", near(r.was_day_diff, -400.0))

subj, body = digest(since_midnight())
sec = section(body, "CHANGES TO DAYS ALREADY SAVED")
ok("the report calls it out", occursin("It balances now.", sec))
ok("and says what the difference was", occursin("\$400.00", sec))

# =============================================================================
# 8. A gap filled, and the ledger it releases
# =============================================================================
println("\n8. The missing day is entered")

save(day(Date(2026, 2, 6); o = 2100.0, c = 2100.0))
ok("the day before the gap goes in", Chain.on_record(Date(2026, 2, 6)))
ok("and 8 February is still waiting", Chain.waiting_ledgers() == [Date(2026, 2, 8)])

fill = save(day(Date(2026, 2, 7); o = 2100.0, s = 800.0, c = 2900.0))
ok("filling the gap releases the held ledger", Date(2026, 2, 8) in fill.out.released)
ok("and the released day carries its figures",
   length(fill.out.released_days) == 1 && fill.out.released_days[1].date == Date(2026, 2, 8))

r = last_row(Date(2026, 2, 7))
ok("the filler's row is a save", text(r.what) == "saved")
ok("flagged as filling a gap", istrue(r.filled_a_gap))

rel = [x for x in rows_for(Date(2026, 2, 8)) if text(x.what) == "released"]
ok("a released row was written for the day above it", length(rel) == 1)
ok("it names the day that released it", text(rel[end].released_by) == "2026-02-07")
ok("and the ledger was made", text(rel[end].ledger) in ("written", "overwritten"))

subj, body = digest()
gaps = section(body, "GAPS FILLED, AND THE LEDGERS THEY RELEASED")
ok("the report has a gaps section",
   has_section(body, "GAPS FILLED, AND THE LEDGERS THEY RELEASED"))
ok("it names the day that was entered", occursin("7 February 2026", gaps))
ok("and, under it, the ledger that was made", occursin("8 February 2026", gaps))
ok("the filler is not listed as an ordinary day as well",
   !occursin("7 February 2026", section(body, "DAYS ENTERED")))

# =============================================================================
# 9. A difference nobody could see until the gap was filled
# =============================================================================
println("\n9. The difference that only came to light on release")

ok("the released day's overnight difference was worked out against the new day",
   near(rel[end].night_diff, -400.0))
ok("its reason came with it",
   text(rel[end].night_reason) == "Sunday takings banked on Monday")
ok("the report prints the amount", occursin("\$400.00", gaps))
ok("and the reason the person typed at the time",
   occursin("Sunday takings banked on Monday", gaps))

println("\n   A release that cannot be made silently")
save(day(Date(2026, 2, 10); o = 3000.0, c = 3000.0))     # no reason on record
ok("a second day waits on its own gap",
   Chain.waiting_ledgers() == [Date(2026, 2, 10)])
stuck = save(day(Date(2026, 2, 9); o = 2500.0, c = 2500.0))
ok("filling that gap does NOT release it — the difference has no reason",
   !(Date(2026, 2, 10) in stuck.out.released))
ok("so it is still waiting", Date(2026, 2, 10) in Chain.waiting_ledgers())
ok("and no released row was invented for it",
   isempty([x for x in rows_for(Date(2026, 2, 10)) if text(x.what) == "released"]))

save(day(Date(2026, 2, 10); o = 3000.0, c = 3000.0,
         opening_reason = "Float topped up from the bank run"))
ok("saying what happened makes the ledger", isfile(daily_ledger_path(Date(2026, 2, 10))))

# =============================================================================
# 10. The list of ledgers still waiting
# =============================================================================
println("\n10. Ledgers still waiting")

w = section(WAITING_WHILE_HELD, "LEDGERS STILL WAITING")
ok("while one was waiting, the report had the section",
   has_section(WAITING_WHILE_HELD, "LEDGERS STILL WAITING"))
ok("it named the day that is waiting", occursin("8 February 2026", w))
ok("and the day that has to be entered first", occursin("7 February 2026", w))

ok("with everything entered, nothing is waiting", isempty(Chain.waiting_ledgers()))
subj, body = digest()
ok("and the report drops the section entirely",
   !has_section(body, "LEDGERS STILL WAITING"))

# =============================================================================
# 11. The words the owner reads
# =============================================================================
println("\n11. Plain words, plain money, plain dates")

subj, body = digest()
ok("no warning code is anywhere in the report",
   !any(c -> occursin(c, body) || occursin(c, subj), ["L1-", "L2-", "L3-", "L4-"]))

amounts = [m.match for m in eachmatch(r"\$[0-9][0-9,]*(\.[0-9]+)?", body)]
ok("the report does talk about money", !isempty(amounts))
bad = filter(a -> !occursin(r"^\$\d{1,3}(,\d{3})*\.\d\d$", a), amounts)
ok("and every amount is written \$5,000.00", isempty(bad) || (println("      -> $bad"); false))

# The one line that legitimately carries a file path is not prose.
prose = join([l for l in split(body, '\n') if !startswith(strip(l), "Records folder")], "\n")
ok("no date is written 2026-02-07", !occursin(r"\d{4}-\d{2}-\d{2}", prose))
ok("dates are spoken out loud instead", occursin("February 2026", body))
ok("the subject carries the clinic's prefix", startswith(subj, "ldgr: "))
ok("and says what it is", occursin("report for", subj))

# =============================================================================
# 12. A quiet day still gets a report
# =============================================================================
println("\n12. A day on which nothing happened")

qsubj, qbody = digest(DateTime(2020, 1, 1), DateTime(2020, 1, 2))
ok("it says so in one sentence",
   occursin("Nothing was entered or changed today, and every recorded day has its ledger.", qbody))
ok("with no sections at all", !any(h -> has_section(qbody, h), HEADINGS))
ok("and the subject says there is nothing to report",
   occursin("nothing to report", qsubj))

# =============================================================================
# 13. An Off day
# =============================================================================
println("\n13. An Off day")

off = save(closed_day(Date(2026, 2, 11), 3000.0))
ok("it saves", off.out.ok && off.out.closed)
r = last_row(Date(2026, 2, 11))
ok("the log calls it a closed day", text(r.kind) == "closed")
ok("with no ledger to make", text(r.ledger) == "not applicable (closed)")
ok("and no difference", near(r.day_diff, 0.0) && near(r.night_diff, 0.0))

subj, body = digest()
ok("the report lists it as an Off day",
   occursin("11 February 2026 — Off day.", body))
ok("and it is not on the waiting list", isempty(Chain.waiting_ledgers()))

# =============================================================================
# 14. A day that was refused
# =============================================================================
println("\n14. A save the checks refused")

before_count = nrows()
refused() =
    try
        save(day(Date(2026, 2, 12); o = 3000.0, s = 500.0, c = 3000.0))   # no reason
        false
    catch
        true
    end
ok("the day is refused", refused())
ok("nothing was written to the books", !Chain.on_record(Date(2026, 2, 12)))
ok("and nothing was written to the log", nrows() == before_count)
ok("so the day has never been seen", Changes.first_seen(Date(2026, 2, 12)) === nothing)

subj, body = digest()
ok("the report does not mention it", !occursin("12 February 2026", body))

# =============================================================================
# 15. Which report is owed, and which is coming
# =============================================================================
println("\n15. The 5:30 pm cutoff")

const AT = Time(17, 30)
ok("the report goes out at 5:30 pm unless notify.toml says otherwise",
   Notify.DEFAULT_SEND_AT == AT)
ok("and notify.toml's send_at is read as 17:30",
   Notify.settings().send_at == AT && Notify.send_at_text() == "17:30")

ok("at 5:29 pm the report owed is yesterday's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 17, 29), AT) == DateTime(2026, 2, 19, 17, 30))
ok("and the coming one is today's",
   Notify.next_cutoff(DateTime(2026, 2, 20, 17, 29), AT) == DateTime(2026, 2, 20, 17, 30))
ok("at 5:30 pm exactly the report owed is today's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 17, 30), AT) == DateTime(2026, 2, 20, 17, 30))
ok("and the coming one is tomorrow's",
   Notify.next_cutoff(DateTime(2026, 2, 20, 17, 30), AT) == DateTime(2026, 2, 21, 17, 30))
ok("at 5:31 pm the report owed is still today's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 17, 31), AT) == DateTime(2026, 2, 20, 17, 30))
ok("and the coming one is tomorrow's",
   Notify.next_cutoff(DateTime(2026, 2, 20, 17, 31), AT) == DateTime(2026, 2, 21, 17, 30))
ok("just after midnight the report owed is yesterday's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 0, 1), AT) == DateTime(2026, 2, 19, 17, 30))
ok("and the coming one is later that day",
   Notify.next_cutoff(DateTime(2026, 2, 20, 0, 1), AT) == DateTime(2026, 2, 20, 17, 30))
ok("the coming report after the last send time of the year is on 1 January",
   Notify.next_cutoff(DateTime(2026, 12, 31, 18, 0), AT) == DateTime(2027, 1, 1, 17, 30))

write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = \"half past five\""))
ok("a send time that cannot be read falls back to 5:30 pm rather than stopping the report",
   Notify.settings() !== nothing && Notify.settings().send_at == AT)
write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = 18:15:00"))
ok("a TOML time written without quotes is taken as it is",
   Notify.settings() !== nothing && Notify.settings().send_at == Time(18, 15))
write(CONFIG, SETTINGS)
ok("and back to 17:30", Notify.settings().send_at == AT)

# =============================================================================
# 16. Handing the coming report to Resend
# =============================================================================
println("\n16. The first hand-over, no change, and a save")

# Everything from here to group 24 happens in March 2031. The marker is set to
# the evening before, so every real row written above is outside every window.
const M0   = DateTime(2031, 3, 2, 17, 30)
const CUT1 = DateTime(2031, 3, 3, 17, 30)
fresh_schedule!(M0)

Notify.MAILER[] = nothing
ok("with email on but nothing to send with (the command line), a tick says so",
   tick_at(DateTime(2031, 3, 3, 8, 0)) == [:no_mailer])
ok("and writes nothing", !isfile(statefile()) && Notify.last_reported() == M0)
Notify.MAILER[] = FAKE

t1 = DateTime(2031, 3, 3, 9, 0)
res = tick_at(t1)
ok("the first tick of the day hands a report over", res == [:scheduled])
ok("one email, and nothing cancelled", length(CREATES) == 1 && isempty(CANCELS))
c1 = created()
ok("it was handed the key from notify.toml", c1.key == KEY)
ok("addressed to the owner, as a list", get(c1.email, "to", nothing) == ["owner@example.invalid"])
ok("from the address in notify.toml", get(c1.email, "from", "") == FROM)
ok("with a quiet subject", subject_of(c1) == "ldgr: report for 3 March 2031 — nothing to report")
ok("to be sent at 5:30 pm, written in UTC",
   sched_of(c1) == Notify._utc_text(CUT1) &&
   occursin(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:00\.000Z$", something(sched_of(c1), "")))
ok("a quiet report says so in one sentence",
   occursin("Nothing was entered or changed today, and every recorded day has its ledger.", body_of(c1)))
ok("with nothing saved there is no 'saved up to' line",
   !occursin("Includes everything saved up to", body_of(c1)))
ok("the footer gives the send time in words",
   occursin("This report is sent at 5:30 pm on each day ldgr is used. If none arrives on a " *
            "working day, ldgr was not opened that day or the email settings need attention.",
            flat(body_of(c1))))
p1 = keyparts(c1.idem)
ok("the idempotency key is ldgr-<cutoff>-g<generation>-<hash>",
   p1 !== nothing && p1[1] == "203103031730")
st = state()
ok("the state file names the version waiting", get(st, "id", "") == c1.id)
ok("and when it goes", get(st, "cutoff", "") == "2031-03-03 17:30:00")
ok("and where its stretch starts", get(st, "from", "") == "2031-03-02 17:30:00")
ok("and how many rows it was built from", get(st, "rows", -1) == 0)
ok("and its generation, the one in the key", get(st, "generation", -1) == keygen(c1.idem))
ok("a new record starts its generation from the clock, not from 0",
   get(st, "generation", -1) == Dates.value(t1 - DateTime(2026)) ÷ 1000 + 1)
ok("with nothing to cancel", isempty(get(st, "cancel", Any[1])))
ok("and a fingerprint of the settings", occursin(r"^[0-9a-f]{16}$", string(get(st, "settings", ""))))
ok("handing a report over does not move the marker", Notify.last_reported() == M0)
ok("the audit log says it was handed over, and when it goes",
   occursin("email: the report for 3 March 2031 was handed to Resend, to be sent at 5:30 pm " *
            "(nothing saved in it)", auditlog()))

res = tick_at(DateTime(2031, 3, 3, 9, 1))
ok("a minute later, with nothing changed, nothing is done", res == [:idle])
res = tick_at(DateTime(2031, 3, 3, 9, 2); poked = true)
ok("a poke with nothing changed does nothing either", res == [:idle])
ok("and nothing more reached Resend", length(CREATES) == 1 && isempty(CANCELS) && SEND_TRIES[] == 1)

println("\n   A day is saved")
logged!(DateTime(2031, 3, 3, 10, 0, 0), Date(2031, 3, 3))
res = tick_at(DateTime(2031, 3, 3, 10, 0, 30))
ok("the save brings a new version and cancels the old", res == [:scheduled, :cancelled])
c2 = created()
ok("the new version was handed over FIRST, then the old one cancelled",
   EVENTS == ["create:$(c1.id)", "create:$(c2.id)", "cancel:$(c1.id)"])
ok("the cancel used the same key", !isempty(CANCELS) && CANCELS[end].key == KEY)
ok("the new version names the day", subject_of(c2) == "ldgr: report for 3 March 2031 — 1 day entered")
ok("and shows it", occursin("3 March 2031 — balanced.", body_of(c2)) &&
                   occursin("Entered by tester at 10:00 am.", body_of(c2)))
ok("and says how current it is", occursin("Includes everything saved up to 10:00 am on 3 March.", body_of(c2)))
st = state()
ok("the state file now names the new version", get(st, "id", "") == c2.id && get(st, "rows", -1) == 1)
ok("its generation went up by one", get(st, "generation", -1) == keygen(c1.idem) + 1 &&
                                    keygen(c2.idem) == keygen(c1.idem) + 1)
ok("and nothing is left to cancel", isempty(get(st, "cancel", Any[1])))
al = auditlog()
ok("the audit log has the new hand-over with its 'saved up to' time",
   occursin("email: the report for 3 March 2031 was handed to Resend, to be sent at 5:30 pm " *
            "(includes everything saved up to 10:00 am on 3 March)", al))
ok("and the cancel", occursin("email: an earlier version of the report for 3 March 2031 was cancelled", al))

# =============================================================================
# 17. Idempotency keys
# =============================================================================
println("\n17. A retry can never make a second email")

rows17, prob17 = Changes.rows_checked(M0, CUT1)
s17, b17, h17 = Notify._report(rows17, prob17, M0, CUT1)
e17 = Notify._email(Notify.settings(), s17, b17; scheduled_at = Notify._utc_text(CUT1), html = h17)
ok("rebuilding the same books gives the same email, byte for byte", e17 == c2.email)
ok("and so the same content hash in the key", keyhash(c2.idem) == Notify._hash16(e17))
ok("a second rebuild is identical again", Notify._digest(rows17, prob17, M0, CUT1) == (s17, b17) &&
                                          Notify._report(rows17, prob17, M0, CUT1) == (s17, b17, h17))

println("\n   Resend takes the email but the answer is lost")
logged!(DateTime(2031, 3, 3, 11, 0, 0), Date(2031, 3, 1))
LOSE_REPLY[] = true
n0 = length(CREATES); ids0 = FAKE_IDS[]
res = tick_at(DateTime(2031, 3, 3, 11, 0, 30))
ok("the hand-over counts as failed", res == [:failed])
ok("the state file still names the older version", get(state(), "id", "") == c2.id)
ok("a five-minute pause started", Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :temporary)
res = tick_at(DateTime(2031, 3, 3, 11, 1, 30); poked = true)
ok("the next save's poke tries again at once", res == [:scheduled, :cancelled])
ok("with exactly the same idempotency key",
   length(CREATES) == n0 + 2 && CREATES[n0 + 1].idem == CREATES[n0 + 2].idem)
ok("so Resend answers with the email it already made: still only one new email",
   FAKE_IDS[] == ids0 + 1 && created().id == CREATES[n0 + 1].id)
ok("the state file names it", get(state(), "id", "") == created().id)
ok("the pause is over", Notify.BACKOFF[] === nothing)
c3 = created()

println("\n   The state file is lost")
rm(statefile())
nc = length(CANCELS)
res = tick_at(DateTime(2031, 3, 3, 11, 5))
c4 = created()
ok("a new version is handed over", res == [:scheduled])
ok("with the same content as the one the lost record held", c4.email == c3.email)
ok("but a different idempotency key", c4.idem != c3.idem && keyhash(c4.idem) == keyhash(c3.idem))
ok("because the generation changed — taken from the clock, not restarted at 0",
   keygen(c4.idem) == Dates.value(DateTime(2031, 3, 3, 11, 5) - DateTime(2026)) ÷ 1000 + 1 &&
   keygen(c4.idem) != keygen(c3.idem))
ok("so Resend makes a new email rather than handing back an old one", c4.id != c3.id)
ok("the lost version cannot be cancelled: nothing names it any more", length(CANCELS) == nc)

println("\n   The state file cannot be read")
write(statefile(), "this is [[[ not a toml file\n")
res = tick_at(DateTime(2031, 3, 3, 11, 6))
ok("a fresh record is started and a version handed over", res == [:scheduled])
ok("the audit log says the record could not be read",
   occursin("email: the record of the report waiting at Resend could not be read, so a new one was started",
            auditlog()))
ok("the state file is readable again", get(state(), "id", "") == created().id)
c5 = created()

# =============================================================================
# 18. The last minute, a correction, and settling
# =============================================================================
println("\n18. A save in the last minute, and what happens after 5:30 pm")

logged!(DateTime(2031, 3, 3, 17, 29, 10), Date(2031, 2, 28))
n0 = length(CREATES)
res = tick_at(DateTime(2031, 3, 3, 17, 29, 30))
ok("within a minute of the send time nothing is handed over", res == [:idle])
ok("nothing reached Resend", length(CREATES) == n0 && SEND_TRIES[] == n0)
ok("the waiting version is unchanged", get(state(), "id", "") == c5.id && get(state(), "rows", -1) == 2)

res = tick_at(DateTime(2031, 3, 3, 17, 31))
ok("after 5:30 pm a corrected report goes out, and tomorrow's is handed over",
   res == [:sent, :scheduled])
fix = created(-1); nxt = created()
ok("the correction is sent now, with no send time", length(CREATES) == n0 + 2 && sched_of(fix) === nothing)
ok("its key says it is a correction", startswith(fix.idem, "ldgr-fix-203103031730-"))
ok("its subject says it is a corrected report",
   subject_of(fix) == "ldgr: corrected report for 3 March 2031 — 3 days entered")
ok("its first line says what it replaces and why",
   first_para(body_of(fix)) == "This replaces the report sent at 5:30 pm, which was prepared " *
                               "before the last entry of that day could be sent.")
ok("it includes the late save", occursin("28 February 2031 — balanced.", body_of(fix)) &&
                                occursin("Includes everything saved up to 5:29 pm on 3 March.", body_of(fix)))
ok("the marker moved to that evening", Notify.last_reported() == CUT1)
ok("tomorrow's report waits for tomorrow at 5:30 pm",
   sched_of(nxt) == Notify._utc_text(DateTime(2031, 3, 4, 17, 30)) &&
   subject_of(nxt) == "ldgr: report for 4 March 2031 — nothing to report")
ok("and covers from this evening", occursin("covering 3 March 5:30 pm to 4 March 5:30 pm", body_of(nxt)))
st = state()
ok("the state file names tomorrow's version",
   get(st, "id", "") == nxt.id && get(st, "cutoff", "") == "2031-03-04 17:30:00" &&
   get(st, "from", "") == "2031-03-03 17:30:00" && get(st, "rows", -1) == 0)
ok("the version that already went out is not on the cancel list", isempty(get(st, "cancel", Any[1])))
ok("the audit log says a correction was sent, and why",
   occursin("email: a corrected report for 3 March 2031 was sent, because something was saved " *
            "after the last version was handed over (includes everything saved up to 5:29 pm on 3 March)",
            auditlog()))

println("\n   The next evening, with nothing saved")
n0 = length(CREATES)
res = tick_at(DateTime(2031, 3, 4, 17, 35))
ok("the version Resend sent is settled and the next one handed over", res == [:settled, :scheduled])
ok("the marker moved to that send time", Notify.last_reported() == DateTime(2031, 3, 4, 17, 30))
ok("nothing was sent straight away",
   length(CREATES) == n0 + 1 && sched_of(created()) == Notify._utc_text(DateTime(2031, 3, 5, 17, 30)))
ok("the audit log says the report was complete",
   occursin("email: the report for 4 March 2031, sent by Resend at 5:30 pm, held every entry up to that time",
            auditlog()))
ok("and the start-up line names the last complete report",
   occursin("last complete report: 5:30 pm on 4 March 2031", Notify.banner()))

# =============================================================================
# 19. Days ldgr was not opened
# =============================================================================
println("\n19. Three quiet days closed, then days typed on the command line")

n0 = length(CREATES)
res = tick_at(DateTime(2031, 3, 8, 10, 0))
ok("the version for the 5th is settled; the quiet days send nothing of their own",
   res == [:settled, :scheduled] && length(CREATES) == n0 + 1)
ok("the marker is at the last report that went", Notify.last_reported() == DateTime(2031, 3, 5, 17, 30))
fold = created()
ok("the coming report starts where the last one ended",
   get(state(), "from", "") == "2031-03-05 17:30:00" &&
   occursin("covering 5 March 5:30 pm to 8 March 5:30 pm", body_of(fold)))
ok("its subject names the whole stretch", subject_of(fold) == "ldgr: report for 5–8 March 2031 — nothing to report")
ok("and it says it covers more than one day",
   occursin("This report covers more than one day: no report was sent at 5:30 pm on the days in " *
            "between, usually because ldgr was not opened.", flat(body_of(fold))))
ok("a quiet stretch says so", occursin("Nothing was entered or changed, and every recorded day has its ledger.",
                                       body_of(fold)))
ok("it is not a late report", !occursin("This report is late", body_of(fold)))

println("\n   Saved on the command line while the server was closed")
logged!(DateTime(2031, 3, 8, 12, 15), Date(2031, 3, 8))
logged!(DateTime(2031, 3, 9, 11, 20), Date(2031, 3, 9))
n0 = length(CREATES)
res = tick_at(DateTime(2031, 3, 10, 9, 0))
ok("the next start sends a correction, a late report, and hands over today's",
   res == [:sent, :late, :scheduled] && length(CREATES) == n0 + 3)
fix = created(-2); late = created(-1); nxt = created()
ok("the 8th's report missed a save made after it was handed over, so it is corrected",
   subject_of(fix) == "ldgr: corrected report for 5–8 March 2031 — 1 day entered" &&
   sched_of(fix) === nothing && occursin("8 March 2031 — balanced.", body_of(fix)))
ok("the 9th was never handed over, so it goes now as a late report",
   sched_of(late) === nothing && startswith(late.idem, "ldgr-late-203103091730-"))
ok("its subject names the day", subject_of(late) == "ldgr: report for 9 March 2031 — 1 day entered")
ok("and it says why it is late",
   first_para(body_of(late)) == "This report is late: it could not be sent at 5:30 pm, usually " *
                                "because ldgr was closed or offline before it could hand the report over.")
ok("it covers its own stretch", occursin("covering 8 March 5:30 pm to 9 March 5:30 pm", body_of(late)) &&
                                occursin("Includes everything saved up to 11:20 am on 9 March.", body_of(late)))
ok("the marker is at the late report's cutoff", Notify.last_reported() == DateTime(2031, 3, 9, 17, 30))
ok("today's report starts there",
   sched_of(nxt) == Notify._utc_text(DateTime(2031, 3, 10, 17, 30)) &&
   occursin("covering 9 March 5:30 pm to 10 March 5:30 pm", body_of(nxt)))
ok("the audit log names the late report",
   occursin("email: a late report covering 9 March 2031 was sent (includes everything saved up to " *
            "11:20 am on 9 March)", auditlog()))

println("\n   The very first report, with no marker at all")
fresh_schedule!(nothing)
res = tick_at(DateTime(2031, 3, 12, 9, 0))
ok("everything in the log goes at once, then today's is handed over", res == [:late, :scheduled])
first_rep = created(-1)
ok("it says it is the first report, not a late one",
   startswith(first_para(body_of(first_rep)),
              "This is the first report since email was set up, so it covers everything in the " *
              "change log up to 5:30 pm on 11 March 2031.") &&
   !occursin("This report is late", body_of(first_rep)))
ok("and it covers everything", occursin("covering everything up to 11 March 5:30 pm", body_of(first_rep)))
ok("the marker is set by it", Notify.last_reported() == DateTime(2031, 3, 11, 17, 30))

# =============================================================================
# 20. Cancels that fail
# =============================================================================
println("\n20. An earlier version that cannot be cancelled")

fresh_schedule!(DateTime(2031, 3, 14, 17, 30))
tick_at(DateTime(2031, 3, 15, 9, 0))
vA = created().id
CANCEL_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the " *
                                           "connection could not be opened. (test: cancel outage)")
logged!(DateTime(2031, 3, 15, 10, 0), Date(2031, 3, 15))
res = tick_at(DateTime(2031, 3, 15, 10, 0, 30))
vB = created().id
ok("the new version is handed over although the cancel fails", res == [:scheduled] && vB != vA)
ok("the old one's cancel was tried straight away", CANCEL_TRIES[] == 1)
st = state()
ok("and it is kept, with its own send time",
   get(st, "cancel", Any[]) == [Dict{String,Any}("id" => vA, "cutoff" => "2031-03-15 17:30:00")])
raw = read(statefile(), String)
ok("written as a [[cancel]] table", occursin("[[cancel]]", raw))
ok("a cancel pause started", Notify.CANCEL_BACKOFF[] !== nothing && Notify.CANCEL_BACKOFF[].kind === :temporary)
ok("but not a hand-over pause", Notify.BACKOFF[] === nothing)

res = tick_at(DateTime(2031, 3, 15, 10, 2))
ok("two minutes later the cancel is not tried again yet", res == [:idle] && CANCEL_TRIES[] == 1)
res = tick_at(DateTime(2031, 3, 15, 10, 6))
ok("after five minutes it is", res == [:idle] && CANCEL_TRIES[] == 2)
ok("and, still failing, it stays on the list", leftovers() == [vA])
CANCEL_FAIL[] = nothing
res = tick_at(DateTime(2031, 3, 15, 10, 12))
ok("when Resend answers, the old version is cancelled", res == [:cancelled] &&
                                                        !isempty(CANCELS) && CANCELS[end].id == vA)
ok("and the list is empty", isempty(leftovers()))
ok("the audit log says so",
   occursin("email: an earlier version of the report for 15 March 2031 was cancelled", auditlog()))

println("\n   A key that can only send")
const FULL = "The Resend API key in notify.toml can only send; make a Full access key so an " *
             "earlier version of the report can be cancelled."
CANCEL_FAIL[] = Resend.Failure(:settings, FULL)
logged!(DateTime(2031, 3, 15, 11, 0), Date(2031, 3, 14))
res = tick_at(DateTime(2031, 3, 15, 11, 0, 30))
vC = created().id
ok("a new version is still handed over", res == [:scheduled] && leftovers() == [vB])
ok("the audit log says to make a Full access key", occursin("email: " * FULL, auditlog()))
ok("that cancel pause lasts until the settings change",
   Notify.CANCEL_BACKOFF[] !== nothing && Notify.CANCEL_BACKOFF[].kind === :settings)
logged!(DateTime(2031, 3, 15, 11, 30), Date(2031, 3, 13))
t0 = CANCEL_TRIES[]
res = tick_at(DateTime(2031, 3, 15, 11, 30, 30))
ok("the next save is handed over too — failing cancels never block a hand-over", res == [:scheduled])
ok("straight after it, one cancel is tried despite the pause", CANCEL_TRIES[] == t0 + 1)
ok("both earlier versions wait on the list", leftovers() == [vB, vC])

d0 = count_of("could not be cancelled before 5:30 pm, so it may also have been sent", auditlog())
t0 = CANCEL_TRIES[]
res = tick_at(DateTime(2031, 3, 15, 17, 31))
ok("after their send time they are dropped without being tried",
   CANCEL_TRIES[] == t0 && isempty(leftovers()))
ok("and the version that went out is settled as usual", res == [:settled, :scheduled])
ok("the audit log says each of the two may also have been sent",
   count_of("could not be cancelled before 5:30 pm, so it may also have been sent", auditlog()) == d0 + 2 &&
   occursin("email: an earlier version of the report for 15 March 2031 could not be cancelled " *
            "before 5:30 pm, so it may also have been sent", auditlog()))
CANCEL_FAIL[] = nothing

# =============================================================================
# 21. When the report cannot be handed over
# =============================================================================
println("\n21. No internet, then the wrong settings")

fresh_schedule!(DateTime(2031, 3, 17, 17, 30))
const OUTAGE = "The internet or Resend could not be reached: the connection could not be opened. " *
               "(test outage 21)"
SEND_FAIL[] = Resend.Failure(:temporary, OUTAGE)
a0 = count_of(OUTAGE, auditlog())
res = tick_at(DateTime(2031, 3, 18, 9, 0))
ok("with no internet the hand-over fails", res == [:failed] && SEND_TRIES[] == 1 && isempty(CREATES))
ok("a five-minute pause starts",
   Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :temporary &&
   Notify.BACKOFF[].until == DateTime(2031, 3, 18, 9, 5))
ok("the audit log says what is wrong", count_of(OUTAGE, auditlog()) == a0 + 1)
ok("nothing is recorded as waiting at Resend", isfile(statefile()) && get(state(), "id", "x") == "")
res = tick_at(DateTime(2031, 3, 18, 9, 2))
ok("two minutes later the timer waits", res == [:waiting] && SEND_TRIES[] == 1)
res = tick_at(DateTime(2031, 3, 18, 9, 3); poked = true)
ok("a save's poke does not wait out a temporary pause", res == [:failed] && SEND_TRIES[] == 2)
res = tick_at(DateTime(2031, 3, 18, 9, 6))
ok("the timer waits five minutes from that attempt", res == [:waiting] && SEND_TRIES[] == 2)
res = tick_at(DateTime(2031, 3, 18, 9, 9))
ok("then tries again", res == [:failed] && SEND_TRIES[] == 3)
ok("the same failure is written once, not every five minutes", count_of(OUTAGE, auditlog()) == a0 + 1)
res = tick_at(DateTime(2031, 3, 18, 10, 10))
ok("an hour on, still failing, it is written again",
   res == [:failed] && count_of(OUTAGE, auditlog()) == a0 + 2)
SEND_FAIL[] = nothing
res = tick_at(DateTime(2031, 3, 18, 10, 20))
ok("when the internet is back the report is handed over", res == [:scheduled])
ok("and the pause is over", Notify.BACKOFF[] === nothing)

println("\n   A failure whose text quotes the key")
SEND_FAIL[] = ErrorException("request failed; header was Authorization: Bearer $(KEY)")
logged!(DateTime(2031, 3, 18, 10, 30), Date(2031, 3, 18))
res = tick_at(DateTime(2031, 3, 18, 10, 30, 30))
ok("an unexpected error is a failure", res == [:failed])
ok("and counts as temporary", Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :temporary)
ok("its words reach the audit log with the key blanked out",
   occursin("email: The report could not be handed to Resend: request failed; header was " *
            "Authorization: Bearer ********", auditlog()))
SEND_FAIL[] = Resend.Failure(:settings, "Resend said: bad key $(KEY)")
res = tick_at(DateTime(2031, 3, 18, 10, 31); poked = true)
ok("so does a Resend.Failure that quotes it", res == [:failed] &&
                                              occursin("email: Resend said: bad key ********", auditlog()))
ok("THE KEY IS NOT IN THE AUDIT LOG", !occursin(KEY, auditlog()))
SEND_FAIL[] = nothing

println("\n   The owner-address rule")
fresh_schedule!(DateTime(2031, 3, 19, 17, 30))
const OWN = "Resend only sends to the address the Resend account was opened with; " *
            "`to` in notify.toml must be that address."
SEND_FAIL[] = Resend.Failure(:settings, OWN)
res = tick_at(DateTime(2031, 3, 20, 9, 0))
ok("a settings refusal fails the hand-over", res == [:failed])
ok("and starts an hour's pause",
   Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :settings &&
   Notify.BACKOFF[].until == DateTime(2031, 3, 20, 10, 0))
ok("the audit log says what to fix", occursin("email: " * OWN, auditlog()))
res = tick_at(DateTime(2031, 3, 20, 9, 30))
ok("half an hour later the timer still waits", res == [:waiting] && SEND_TRIES[] == 1)
res = tick_at(DateTime(2031, 3, 20, 9, 31); poked = true)
ok("and so does a save's poke: only a person can fix this", res == [:waiting] && SEND_TRIES[] == 1)
ok("notify.toml is saved again", bump_config!())
res = tick_at(DateTime(2031, 3, 20, 9, 32))
ok("which ends the pause at once", res == [:failed] && SEND_TRIES[] == 2)
res = tick_at(DateTime(2031, 3, 20, 9, 40))
ok("the new failure starts a new pause", res == [:waiting] && SEND_TRIES[] == 2)
SEND_FAIL[] = nothing
res = tick_at(DateTime(2031, 3, 20, 10, 31))
ok("left alone, the pause lasts the hour", res == [:waiting] && SEND_TRIES[] == 2)
res = tick_at(DateTime(2031, 3, 20, 10, 32))
ok("and then the hand-over is tried, and works", res == [:scheduled] && SEND_TRIES[] == 3)

# =============================================================================
# 22. The clock
# =============================================================================
println("\n22. A marker from the future, and the time Resend is given")

Notify.mark_reported!(DateTime(2031, 3, 22, 9, 3))
m, note = Notify._marker(DateTime(2031, 3, 22, 9, 0), AT)
ok("a marker three minutes ahead is believed", m == DateTime(2031, 3, 22, 9, 3) && note == "")
Notify.mark_reported!(DateTime(2031, 3, 22, 9, 10))
m, note = Notify._marker(DateTime(2031, 3, 22, 9, 0), AT)
ok("one ten minutes ahead is not", m == DateTime(2031, 3, 20, 17, 30) && !isempty(note))

const FUTURE = DateTime(2031, 4, 20, 17, 30)
fresh_schedule!(FUTURE)
res = tick_at(DateTime(2031, 3, 22, 9, 0))
ok("with a marker a month ahead, the report is still handed over", res == [:scheduled])
fut = created()
ok("starting a day before the last send time instead",
   get(state(), "from", "") == "2031-03-20 17:30:00" &&
   occursin("covering 20 March 5:30 pm to 22 March 5:30 pm", body_of(fut)))
ok("and saying why, so somebody looks at the clock",
   occursin("The record of the last report was dated 5:30 pm on 20 April 2031, which is in the " *
            "future, so it was ignored and this report starts at 5:30 pm on 20 March 2031. The " *
            "computer's clock may have been wrong.", flat(body_of(fut))))
ok("the marker itself is left alone for now", Notify.last_reported() == FUTURE)
res = tick_at(DateTime(2031, 3, 22, 17, 31))
ok("once that report has gone it is settled", res == [:settled, :scheduled])
ok("and the marker is put right", Notify.last_reported() == DateTime(2031, 3, 22, 17, 30))
ok("the next report has no note about the clock", !occursin("in the future", body_of(created())))

ok("5:30 pm in Guyana is 21:30 UTC",
   Notify._utc_text(DateTime(2026, 9, 28, 17, 30); offset = Minute(-240)) == "2026-09-28T21:30:00.000Z")
ok("and a late evening crosses into the next UTC day",
   Notify._utc_text(DateTime(2026, 12, 31, 21, 30); offset = Minute(-240)) == "2027-01-01T01:30:00.000Z")
ok("the machine's own offset is used, to the minute",
   abs(Dates.value(Notify._utc_offset())) <= 14 * 60 &&
   occursin(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:00\.000Z$", Notify._utc_text(DateTime(2031, 3, 22, 17, 30))))
ok("every scheduled version so far carried its cutoff in that form",
   all(c -> sched_of(c) === nothing ||
            occursin(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:00\.000Z$", sched_of(c)), ALL_CREATES))

# =============================================================================
# 23. A report on request
# =============================================================================
println("\n23. LDGR_DIGEST_NOW: everything so far, now")

fresh_schedule!(DateTime(2031, 3, 23, 17, 30))
tick_at(DateTime(2031, 3, 24, 9, 0))
vA = created().id
logged!(DateTime(2031, 3, 24, 10, 0), Date(2031, 3, 24))
res = tick_at(DateTime(2031, 3, 24, 11, 0); force = true)
ok("a forced tick sends now, hands over a fresh version, and cancels the old",
   res == [:sent, :scheduled, :cancelled])
now_rep = created(-1); nxt = created()
ok("the forced report has no send time and its own kind of key",
   sched_of(now_rep) === nothing && startswith(now_rep.idem, "ldgr-now-203103241100-"))
ok("it covers everything since the marker, up to now",
   occursin("covering 23 March 5:30 pm to 24 March 11:00 am", body_of(now_rep)) &&
   occursin("24 March 2031 — balanced.", body_of(now_rep)))
ok("the marker moved to now", Notify.last_reported() == DateTime(2031, 3, 24, 11, 0))
ok("the fresh version starts there",
   occursin("covering 24 March 11:00 am to 24 March 5:30 pm", body_of(nxt)) &&
   get(state(), "from", "") == "2031-03-24 11:00:00")
ok("and the old version was cancelled", !isempty(CANCELS) && CANCELS[end].id == vA)
ok("the audit log says it was asked for",
   occursin("email: a report covering 24 March 2031 was sent on request (LDGR_DIGEST_NOW)", auditlog()))

# =============================================================================
# 24. Changing notify.toml, and the state file itself
# =============================================================================
println("\n24. The settings change while a version is waiting")

fresh_schedule!(DateTime(2031, 3, 25, 17, 30))
tick_at(DateTime(2031, 3, 26, 9, 0))
vA = created().id
fp0 = get(state(), "settings", "")
write(CONFIG, replace(SETTINGS, "subject_prefix = \"ldgr: \"" => "subject_prefix = \"clinic: \""))
res = tick_at(DateTime(2031, 3, 26, 9, 1))
ok("a new subject prefix replaces the waiting version", res == [:scheduled, :cancelled])
ok("with the new prefix", startswith(subject_of(created()), "clinic: report for 26 March 2031"))
ok("the state file's settings fingerprint changed", get(state(), "settings", "") != fp0)
vB = created().id

CANCEL_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the " *
                                           "connection could not be opened. (test: cancel outage 24)")
write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = \"18:00\""))
res = tick_at(DateTime(2031, 3, 26, 9, 2))
c18 = created()
ok("a new send time hands over a version for that time", res == [:scheduled] &&
   sched_of(c18) == Notify._utc_text(DateTime(2031, 3, 26, 18, 0)))
ok("and the report's words follow the configured time",
   occursin("This report is sent at 6:00 pm on each day ldgr is used.", flat(body_of(c18))))
st = state()
ok("the state file holds exactly the agreed fields",
   Set(keys(st)) == Set(["id", "cutoff", "from", "rows", "generation", "settings", "cancel", "problem"]) &&
   get(st, "problem", nothing) == "")
ok("the waiting version, at its own time",
   get(st, "id", "") == c18.id && get(st, "cutoff", "") == "2031-03-26 18:00:00" &&
   get(st, "from", "") == "2031-03-25 17:30:00" && get(st, "rows", -1) == 0)
ok("and the earlier version still to cancel, at ITS own time",
   get(st, "cancel", Any[]) == [Dict{String,Any}("id" => vB, "cutoff" => "2031-03-26 17:30:00")])
raw = read(statefile(), String)
ok("the file says what it is and not to edit it", startswith(raw, "# Written by ldgr"))
ok("no half-written copy is left beside it",
   !any(f -> endswith(f, ".tmp"), readdir(Layout.notifications_dir())))
ok("and the key is not in it", !occursin(KEY, raw))

t0 = CANCEL_TRIES[]
res = tick_at(DateTime(2031, 3, 26, 17, 45))
ok("at 5:45 pm the 5:30 pm version is dropped, though the waiting one is not due until 6:00 pm",
   isempty(leftovers()) && CANCEL_TRIES[] == t0 && get(state(), "id", "") == c18.id)
ok("and nothing else needed doing", res == [:idle])
ok("the audit log says it may also have been sent",
   occursin("email: an earlier version of the report for 26 March 2031 could not be cancelled " *
            "before 5:30 pm, so it may also have been sent", auditlog()))
CANCEL_FAIL[] = nothing
write(CONFIG, SETTINGS)

# =============================================================================
# 25. Resend.jl against a stub on 127.0.0.1
# =============================================================================
println("\n25. What Resend.jl sends, and how it reads the answers")

ok("Resend.jl waits 10 s to connect and 30 s for an answer unless told otherwise",
   DEFAULT_TIMEOUTS == (connect = 10, read = 30))
Resend.API_BASE[] = "https://example.invalid"
refused_guard = try
    local_only(); false
catch
    true
end
Resend.API_BASE[] = "http://127.0.0.1:$(STUB_PORT)"
ok("the harness refuses to go on if Resend is pointed anywhere but 127.0.0.1", refused_guard)
local_only()
Resend.TIMEOUTS[] = (connect = 2, read = 5)
STUB_MODE[] = :auto
empty!(STUB_HITS)
const EM = Dict{String,Any}("from"         => FROM,
                            "to"           => String["owner@example.invalid"],
                            "subject"      => "ldgr: report for 3 March 2031 — 1 day entered",
                            "text"         => "LDGR DAILY REPORT\n3 March 2031 — balanced.\n" *
                                              "Shortage of \$1,234.00 during the day.",
                            "scheduled_at" => "2031-03-03T21:30:00.000Z")
const IDEM = "ldgr-203103031730-g7-0123456789abcdef"

id = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM))
ok("a send returns the id Resend gave", id == "stub-$(STUB_IDS[])")
ok("one request reached the stub", length(STUB_HITS) == 1)
h = isempty(STUB_HITS) ? (method = "", target = "", headers = Dict{String,String}(), body = "{}") : STUB_HITS[end]
ok("POST /emails", h.method == "POST" && h.target == "/emails")
ok("with the key as a Bearer token", get(h.headers, "authorization", "") == "Bearer $(KEY)")
ok("with the idempotency key", get(h.headers, "idempotency-key", "") == IDEM)
ok("as JSON", get(h.headers, "content-type", "") == "application/json")
jb = try JSON3.read(h.body) catch; nothing end
ok("the body is JSON", jb !== nothing)
jget(o, k) = (o === nothing || !haskey(o, k)) ? nothing : o[k]
ok("from", jget(jb, :from) == EM["from"])
ok("to, as a list", jget(jb, :to) isa AbstractVector && String.(collect(jget(jb, :to))) == ["owner@example.invalid"])
ok("subject", jget(jb, :subject) == EM["subject"])
ok("text, with its dashes and dollars intact", jget(jb, :text) == EM["text"])
ok("scheduled_at", jget(jb, :scheduled_at) == EM["scheduled_at"])

now_email = filter(p -> p.first != "scheduled_at", EM)
via_stub(() -> Resend.send(KEY, now_email; idempotency_key = "ldgr-now-203103031100-0123456789abcdef"))
jb2 = try JSON3.read(STUB_HITS[end].body) catch; nothing end
ok("a report that goes now carries no scheduled_at", jb2 !== nothing && !haskey(jb2, :scheduled_at))

r = via_stub(() -> Resend.cancel(KEY, "stub-1"))
h = STUB_HITS[end]
ok("a cancel returns nothing", r === nothing)
ok("it is POST /emails/<id>/cancel", h.method == "POST" && h.target == "/emails/stub-1/cancel")
ok("with the key as a Bearer token", get(h.headers, "authorization", "") == "Bearer $(KEY)")

STUB_MODE[] = (404, "{\"statusCode\":404,\"name\":\"not_found\",\"message\":\"Email not found\"}", 0.0)
ok("cancelling an email Resend cannot find is not a failure",
   via_stub(() -> Resend.cancel(KEY, "gone")) === nothing)
STUB_MODE[] = (422, "{\"statusCode\":422,\"name\":\"validation_error\",\"message\":\"Email already sent\"}", 0.0)
ok("nor is one that has already gone", via_stub(() -> Resend.cancel(KEY, "sent")) === nothing)

const FAILS = Any[]
function refusal(status, body; cancel = false)
    STUB_MODE[] = (status, body, 0.0)
    e = cancel ? via_stub(() -> Resend.cancel(KEY, "stub-1")) :
                 via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM))
    push!(FAILS, e)
    return e
end

println("\n   Refusals, sorted into the two kinds")
RESTRICTED = "{\"statusCode\":401,\"name\":\"restricted_api_key\",\"message\":\"This API key is restricted to only send emails\"}"
e = refusal(401, RESTRICTED; cancel = true)
ok("401 restricted_api_key on a cancel: settings, and make a Full access key",
   isfailure(e, :settings) && occursin("Full access", e.words))
e = refusal(401, RESTRICTED)
ok("the same on a send", isfailure(e, :settings) && occursin("Full access", e.words))
e = refusal(401, "{\"statusCode\":401,\"name\":\"missing_api_key\",\"message\":\"Missing API key in the authorization header\"}")
ok("401 missing key: settings", isfailure(e, :settings))
e = refusal(403, "{\"statusCode\":403,\"name\":\"invalid_api_key\",\"message\":\"API key is invalid\"}")
ok("403 invalid key: settings", isfailure(e, :settings))
e = refusal(403, "{\"statusCode\":403,\"name\":\"validation_error\",\"message\":\"You can only send " *
                 "testing emails to your own email address (owner@example.invalid). To send emails to " *
                 "other recipients, please verify a domain at resend.com/domains, and change the `from` " *
                 "address to an email using this domain.\"}")
ok("403 own-address rule: settings", isfailure(e, :settings))
ok("saying `to` must be the address the Resend account was opened with",
   e isa Resend.Failure && e.words == OWN)
e = refusal(422, "{\"statusCode\":422,\"name\":\"invalid_parameter\",\"message\":\"Invalid `scheduled_at` field.\"}")
ok("422: settings", isfailure(e, :settings))
e = refusal(429, "{\"statusCode\":429,\"name\":\"daily_quota_exceeded\",\"message\":\"You have reached your daily email sending quota.\"}")
ok("429: temporary", isfailure(e, :temporary))
n0 = length(STUB_HITS)
e = refusal(500, "{\"statusCode\":500,\"name\":\"application_error\",\"message\":\"Internal server error\"}")
ok("500: temporary", isfailure(e, :temporary))
ok("and asked once, not retried behind the caller's back", length(STUB_HITS) == n0 + 1)
e = refusal(409, "{\"statusCode\":409,\"name\":\"concurrent_idempotent_requests\",\"message\":\"Same idempotency key used while original request is still in progress.\"}")
ok("409: temporary", isfailure(e, :temporary))
e = refusal(503, "<html><body><h1>503 Service Unavailable</h1></body></html>")
ok("an error page that is not JSON: still a temporary Failure, nothing else thrown",
   isfailure(e, :temporary))
e = refusal(422, "not json at all {")
ok("a 422 that is not JSON: a settings Failure", isfailure(e, :settings))
e = refusal(200, "<html>ok</html>")
ok("a success with no id in it: a temporary Failure", isfailure(e, :temporary))
e = refusal(422, "{\"statusCode\":422,\"name\":\"validation_error\",\"message\":\"bad header $(KEY)\"}")
ok("Resend's own message is quoted with the key blanked out",
   isfailure(e, :settings) && occursin("********", e.words) && !occursin(KEY, e.words))
n0 = length(STUB_HITS)
e = via_stub(() -> Resend.send("", EM; idempotency_key = IDEM)); push!(FAILS, e)
ok("no key at all: a settings Failure, and nothing is sent", isfailure(e, :settings) && length(STUB_HITS) == n0)

println("\n   A reply too slow, and a connection refused")
Resend.TIMEOUTS[] = (connect = 2, read = 2)
STUB_MODE[] = (200, "{\"id\":\"too-late\"}", 6.0)
t0 = time()
e = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM)); push!(FAILS, e)
dt = time() - t0
ok("a reply slower than the read timeout is temporary",
   isfailure(e, :temporary) && occursin("no answer came within 2 seconds", e.words))
ok("and is given up on in about two seconds (took $(round(dt; digits = 1)) s)", 1.5 <= dt <= 5.0)
STUB_MODE[] = :auto

dead = Sockets.listen(Sockets.ip"127.0.0.1", 0)
dport = Int(Sockets.getsockname(dead)[2])
close(dead)
Resend.API_BASE[] = "http://127.0.0.1:$(dport)"
e = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM)); push!(FAILS, e)
Resend.API_BASE[] = "http://127.0.0.1:$(STUB_PORT)"
ok("a refused connection is temporary",
   dport != STUB_PORT && isfailure(e, :temporary) && occursin("could not be opened", e.words))
ok("and it never left this computer, so the Failure says Resend cannot have made anything",
   e isa Resend.Failure && e.reached === false)

ok("every refusal was a Resend.Failure", all(x -> x isa Resend.Failure, FAILS))
ok("and the key is in none of their words",
   all(x -> !(x isa Resend.Failure) || !occursin(KEY, x.words), FAILS))

# =============================================================================
# 26. One tick, end to end, through Resend.jl and the stub
# =============================================================================
println("\n26. End to end: tick -> Resend.jl -> the stub")

Resend.TIMEOUTS[] = (connect = 2, read = 5)
STUB_MODE[] = :auto
fresh_schedule!(DateTime(2031, 4, 1, 17, 30))
Notify.MAILER[] = (send   = (key, email, idem) -> Resend.send(key, email; idempotency_key = idem),
                   cancel = Resend.cancel)
local_only()
empty!(STUB_HITS)
logged!(DateTime(2031, 4, 2, 10, 0), Date(2031, 4, 2))
res = tick_at(DateTime(2031, 4, 2, 10, 30))
ok("the tick hands the report over through HTTP", res == [:scheduled])
ok("exactly one request arrived", length(STUB_HITS) == 1)
h = isempty(STUB_HITS) ? (method = "", target = "", headers = Dict{String,String}(), body = "{}") : STUB_HITS[1]
ok("a create: POST /emails", h.method == "POST" && h.target == "/emails")
ok("with the key from notify.toml", get(h.headers, "authorization", "") == "Bearer $(KEY)")
ok("with a scheduled idempotency key for 5:30 pm on 2 April",
   (kp = keyparts(get(h.headers, "idempotency-key", "")); kp !== nothing && kp[1] == "203104021730"))
ok("as JSON", get(h.headers, "content-type", "") == "application/json")
jb = try JSON3.read(h.body) catch; nothing end
ok("to the owner, from the address in notify.toml",
   jget(jb, :to) isa AbstractVector && String.(collect(jget(jb, :to))) == ["owner@example.invalid"] &&
   jget(jb, :from) == FROM)
ok("with the report's subject and text",
   jget(jb, :subject) == "ldgr: report for 2 April 2031 — 1 day entered" &&
   occursin("2 April 2031 — balanced.", something(jget(jb, :text), "")))
ok("to be sent at 5:30 pm", jget(jb, :scheduled_at) == Notify._utc_text(DateTime(2031, 4, 2, 17, 30)))
ok("the state file records the id the stub gave", get(state(), "id", "") == "stub-$(STUB_IDS[])")
old = get(state(), "id", "")

logged!(DateTime(2031, 4, 2, 11, 0), Date(2031, 4, 1))
empty!(STUB_HITS)
res = tick_at(DateTime(2031, 4, 2, 11, 0, 30))
ok("a second save: a new version, then the old one cancelled", res == [:scheduled, :cancelled])
ok("two requests, in that order",
   length(STUB_HITS) == 2 && STUB_HITS[1].target == "/emails" &&
   STUB_HITS[2].method == "POST" && STUB_HITS[2].target == "/emails/$(old)/cancel")
ok("the state file names the new id and has nothing left to cancel",
   get(state(), "id", "") == "stub-$(STUB_IDS[])" && get(state(), "id", "") != old && isempty(leftovers()))

STUB_MODE[] = (403, "{\"statusCode\":403,\"name\":\"validation_error\",\"message\":\"You can only send " *
                    "testing emails to your own email address (owner@example.invalid).\"}", 0.0)
logged!(DateTime(2031, 4, 2, 11, 30), Date(2031, 3, 31))
kept = get(state(), "id", "")
a0 = count_of("email: " * OWN, auditlog())
res = tick_at(DateTime(2031, 4, 2, 11, 30, 30))
ok("Resend refusing the address fails the tick", res == [:failed])
ok("the older version stays the one waiting", get(state(), "id", "") == kept)
ok("the audit log says what to fix", count_of("email: " * OWN, auditlog()) == a0 + 1)
ok("and the pause is a settings one", Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :settings)

STUB_MODE[] = :auto
Notify.MAILER[] = FAKE
Notify.BACKOFF[] = nothing
Resend.TIMEOUTS[] = (connect = 2, read = 2)
try
    HTTP.forceclose(STUB)
catch
end
e = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM))
ok("the stub is closed: nothing answers on its port any more", isfailure(e, :temporary))

# =============================================================================
# 27. Never a false all-clear
# =============================================================================
println("\n27. A change log that cannot be read")

const LOGP = Layout.change_log_path()
const LOG_BACKUP = read(LOGP, String)
const N_BEFORE = length(Changes._read_log())

"The change log as it was, with some lines added to the end."
function with_log(extra::AbstractString...)
    open(LOGP, "w") do io
        write(io, LOG_BACKUP)
        endswith(LOG_BACKUP, "\n") || println(io)
        for l in extra
            println(io, l)
        end
    end
end
raw_line(when_text; daydiff = "0.0") =
    join([when_text, "tester", "saved", "2031-05-10", "trading", "added", "written",
          daydiff, "0.0", "", "", "", "", "", "false", "false", "false", "false", ""], ",")

cols = filter(!=("who"), Changes.COLUMNS)
write(LOGP, join(cols, ",") * "\n" *
            join(["2031-05-02 10:00:00", "saved", "2031-05-02", "trading", "added", "written",
                  "0.0", "0.0", "", "", "", "", "", "false", "false", "false", "false", ""], ",") * "\n")
s27, b27 = Notify.build_digest(DateTime(2031, 5, 1, 17, 30), DateTime(2031, 5, 2, 17, 30))
ok("a log with a column missing: the subject says it could not be read",
   startswith(s27, "ldgr: CHANGE LOG COULD NOT BE READ — report for 2 May 2031"))
ok("and never 'nothing to report'", !occursin("nothing to report", s27))
ok("the first thing in the body, before the heading, says so, and that it is not a quiet day",
   startswith(lead_para(b27), "THE CHANGE LOG COULD NOT BE READ PROPERLY, so this report may be " *
                              "missing entries. It is not a quiet day.") &&
   before(b27, "THE CHANGE LOG COULD NOT BE READ PROPERLY", "LDGR DAILY REPORT"))
ok("naming the missing column", occursin("no \"who\" column", b27))
ok("and the all-clear sentence is left out", !occursin("Nothing was entered or changed", b27))

fresh_schedule!(DateTime(2031, 5, 1, 17, 30))
res = tick_at(DateTime(2031, 5, 3, 9, 0))
ok("a stretch the log cannot vouch for is sent at once, not folded", res == [:late, :scheduled])
ok("both emails say the log could not be read",
   length(CREATES) == 2 && all(c -> occursin("CHANGE LOG COULD NOT BE READ", subject_of(c)), CREATES))

with_log(raw_line("2031-05-10 10:00:00"; daydiff = "abc"))
rows27, prob27 = Changes.rows_checked(DateTime(2031, 5, 9, 17, 30), DateTime(2031, 5, 10, 17, 30))
ok("a row with an unreadable figure is named by number",
   prob27 == line_problem(N_BEFORE + 1))
s27, b27 = Notify.build_digest(DateTime(2031, 5, 9, 17, 30), DateTime(2031, 5, 10, 17, 30))
ok("the report for its window says the log could not be read",
   occursin("CHANGE LOG COULD NOT BE READ", s27) && occursin("could not be read", lead_para(b27)) &&
   before(b27, "THE CHANGE LOG COULD NOT BE READ PROPERLY", "LDGR DAILY REPORT") &&
   occursin(line_prefix(N_BEFORE + 1), b27))
ok("and gives no all-clear", !occursin("Nothing was entered or changed", b27))

rows27, prob27 = Changes.rows_checked(DateTime(2031, 5, 20, 17, 30), DateTime(2031, 5, 21, 17, 30))
ok("the same row, readable 'when' outside the window, is not this report's problem", prob27 == "")
s27, b27 = Notify.build_digest(DateTime(2031, 5, 20, 17, 30), DateTime(2031, 5, 21, 17, 30))
ok("so that report is an ordinary quiet one",
   s27 == "ldgr: report for 21 May 2031 — nothing to report" &&
   occursin("Nothing was entered or changed today, and every recorded day has its ledger.", b27))

with_log(raw_line("sometime on Tuesday"; daydiff = "abc"))
ok("a row whose 'when' cannot be read counts against every window",
   !isempty(Changes.rows_checked(DateTime(2031, 5, 20, 17, 30), DateTime(2031, 5, 21, 17, 30))[2]) &&
   occursin("CHANGE LOG COULD NOT BE READ",
            Notify.build_digest(DateTime(2040, 1, 1, 17, 30), DateTime(2040, 1, 2, 17, 30))[1]))

write(LOGP, LOG_BACKUP)
ok("the change log is put back, and reads cleanly",
   Changes.rows_checked(nothing, DateTime(2100, 1, 1))[2] == "" &&
   length(Changes._read_log()) == N_BEFORE)

# =============================================================================
# 28. The next-morning edit
# =============================================================================
println("\n28. A day typed after the send time and corrected the next morning")

nm = save(day(Date(2026, 2, 12); o = 3000.0, c = 3000.0))
ok("the day is saved", nm.out.ok)
ok("its row is moved back to yesterday evening", backdate!(Date(2026, 2, 12)) == 1)
save(day(Date(2026, 2, 12); o = 3000.0, s = 500.0, c = 3500.0))
r = last_row(Date(2026, 2, 12))
ok("the morning correction is a later-date edit",
   r !== nothing && text(r.what) == "edited" && istrue(r.cross_day_edit))

subj, body = digest(now() - Day(2))
blk = block(section(body, "DAYS ENTERED"), "12 February 2026 —")
ok("both rows are in one report, so the day is told once, as entered", !isempty(blk))
ok("and not again under changes",
   !occursin("12 February 2026", section(body, "CHANGES TO DAYS ALREADY SAVED")))
ok("the edit is spelled out with the date, who and when",
   r !== nothing &&
   occursin("   Changed on $(Notify._long(Date(r.when))) by $(r.who) at $(Notify._clock(r.when)):", blk))
ok("with the closing balance before and after", occursin("Closing Balance \$3,000.00 -> \$3,500.00", blk))
ok("and the cash sales before and after", occursin("Cash Sales \$0.00 -> \$500.00", blk))
ok("instead of a bare 'Changed again'", !occursin("Changed again", blk))
ok("nothing is left waiting", isempty(Chain.waiting_ledgers()))

# =============================================================================
# 29. The timer and a save's poke
# =============================================================================
println("\n29. The timer, and a save's poke")

fresh_schedule!(Notify.latest_cutoff(now(), AT))
Notify.start_schedule!()
ok("with LDGR_NO_DIGEST=1 the timer does not start", Notify.SCHEDULE[] === nothing)
ok("and a save's poke returns without doing anything", Notify.poke() === nothing)
sleep(0.5)
ok("no tick ran", SEND_TRIES[] == 0 && !isfile(statefile()))

ENV["LDGR_NO_DIGEST"] = "0"
try
    Notify.start_schedule!()
    tm1 = Notify.SCHEDULE[]
    ok("without it, start_schedule! starts a timer", tm1 isa Timer && isopen(tm1))
    ok("and records it where a second include of server.jl can find it",
       isdefined(Main, :LDGR_REPORT_TIMER) && getfield(Main, :LDGR_REPORT_TIMER) === tm1)
    Notify.start_schedule!()
    tm2 = Notify.SCHEDULE[]
    ok("starting it again closes the first timer: never two schedulers at once",
       tm2 isa Timer && tm2 !== tm1 && !isopen(tm1) && isopen(tm2) &&
       getfield(Main, :LDGR_REPORT_TIMER) === tm2)
    local t0 = time()
    pr = Notify.poke()
    ok("a save's poke returns at once", pr === nothing && time() - t0 < 0.5)
    for _ in 1:50
        isfile(statefile()) && break
        sleep(0.1)
    end
    lock(Notify.BUSY) do
    end                                   # wait for that tick to finish
    ok("and the tick it asked for runs in the background", isfile(statefile()) && SEND_TRIES[] <= 1)
    Notify.stop_schedule!()
    ok("stop_schedule! closes the timer and forgets it",
       !isopen(tm2) && Notify.SCHEDULE[] === nothing && getfield(Main, :LDGR_REPORT_TIMER) === nothing)
finally
    Notify.stop_schedule!()
    ENV["LDGR_NO_DIGEST"] = "1"
end

# =============================================================================
# Helpers for groups 30 to 43
# =============================================================================
# Each of these groups checks one fix from the review of 28 September 2026.
# Every scheduling scenario has a stretch of 2032 to itself, so no group's rows
# fall in another's windows. A group that damages the change log takes a copy
# of it first and puts it back before it ends.

"The change log's raw text, for a group that damages it and puts it back."
logsnap() = read(LOGP, String)

"Append text to the change log exactly as given — no newline unless it is in `s`."
append_raw!(s::AbstractString) = (open(io -> write(io, s), LOGP, "a"); nothing)

"How many data rows the reader finds, readable or not. The next row's number in
a 'Row N could not be read' sentence is one more than this."
nlogrows() = (r = Changes._read_log_checked(); length(r[1]) + length(r[2]))

"Put `line` into the change log straight after its `k`-th data row."
function insert_row!(line::AbstractString, k::Int)
    lines = split(logsnap(), '\n'; keepempty = true)
    insert!(lines, k + 2, line)                  # lines[1] is the header
    write(LOGP, join(lines, '\n'))
    return nothing
end

"One raw change-log line with every cell given. No cell here may hold a comma."
function rawrow(when_text, day_text; what = "saved", who = "tester",
                flags = ("false", "false", "false", "false"), changed = "")
    return join([when_text, who, what, day_text, "trading",
                 what == "edited" ? "replaced" : "added", "written",
                 "0.0", "0.0", "", "", "", "", changed, flags..., ""], ",")
end

"""
One change-log row at a given moment with every cell chosen, written through
Changes._append! exactly as after_save writes one — for the groups that need an
edit, a difference, a gap or a flag at a particular moment.
"""
function logrow!(when::DateTime, d::Date; what = "saved", who = "tester",
                 journal = (what == "edited" ? "replaced" : "added"), ledger = "written",
                 day_diff = 0.0, night_diff = 0.0, reason = "", night_reason = "",
                 was_day = NaN, was_night = NaN, changed = "",
                 cross = false, pending = false, balances = false, gap = false)
    Changes._append!(Changes.Row[Changes.Row((when, who, what, d, "trading", journal, ledger,
                                              day_diff, night_diff, reason, night_reason,
                                              was_day, was_night, changed,
                                              cross, pending, balances, gap, nothing))])
    return nothing
end

last_cancel() = isempty(CANCELS) ? "" : CANCELS[end].id
"The ids of emails the fake made that nothing has cancelled."
live_ids() = setdiff(unique([c.id for c in CREATES]), [c.id for c in CANCELS])
pending_of(st) = get(st, "pending", Dict{String,Any}())

"Does any run of eight characters of the test key appear in `w`?"
leaks_key(w::AbstractString) = any(i -> occursin(KEY[i:i+7], w), 1:length(KEY)-7)

"A logger that keeps every record, with its keywords, for group 34."
struct Capture <: Logging.AbstractLogger
    recs::Vector{Any}
end
Logging.min_enabled_level(::Capture) = Logging.Debug
Logging.shouldlog(::Capture, level, _module, group, id) = true
Logging.catch_exceptions(::Capture) = false
function Logging.handle_message(c::Capture, level, message, _module, group, id, file, line; kwargs...)
    push!(c.recs, (level = level, msg = string(message), mod = string(_module),
                   kw = Dict{Symbol,Any}(kwargs)))
    return nothing
end

"""
Errors named like the ones HTTP.jl's TLS libraries and ConcurrentUtilities
raise, for group 43. Resend._network_words goes by the name of the error's type,
because loading those packages directly is not possible from a test.
"""
module Fakes
struct OpenSSLError <: Exception
    msg::String
end
struct MbedException <: Exception
    ret::Int
end
struct TimeoutException <: Exception
    timeout::Float64
end
end

"The TaskFailedException a task that throws `ex` produces when it is waited on."
function task_error(ex)
    t = Task(() -> throw(ex))
    schedule(t)
    try
        wait(t)
    catch e
        return e
    end
    return ErrorException("the task did not fail")
end

"""
Run a few lines in a separate Julia process that loads main.jl against its own
scratch folder, holding only a copy of the change log given as `log_text`.
Returns (exit code, everything it printed). For a read that can bring the whole
process down (group 32): a crash there must fail a check, not end this run.
The child gets the same safety settings as this run: its LEDGER_ROOT is a fresh
temporary folder, LDGR_NO_DIGEST=1, and notify.toml points at nothing.
"""
function in_child(code::AbstractString, log_text::AbstractString)
    root = mktempdir()
    write(joinpath(root, "Change Log.csv"), log_text)
    script = joinpath(root, "child.jl")
    write(script, "using Dates\ninclude(" * repr(joinpath(@__DIR__, "main.jl")) * ")\n" * code)
    env = copy(ENV)
    env["LEDGER_ROOT"]        = root
    env["LDGR_NO_DIGEST"]     = "1"
    env["LDGR_NO_BROWSER"]    = "1"
    env["LDGR_NOTIFY_CONFIG"] = joinpath(root, "no-such-notify.toml")
    out = IOBuffer()
    p = run(pipeline(ignorestatus(setenv(`$(Base.julia_cmd()) --startup-file=no $(script)`, env));
                     stdout = out, stderr = out))
    return (p.exitcode, String(take!(out)))
end

"What a child process printed after `RESULT <name>=` (or `\"\"`)."
function child_result(out::AbstractString, name::AbstractString)
    m = match(Regex("^RESULT " * name * "=(.*)\$", "m"), out)
    return m === nothing ? "" : String(strip(m.captures[1]))
end

"A spare port on 127.0.0.1, found the way the stub's was."
function spare_port()
    port, tcp = Sockets.listenany(Sockets.ip"127.0.0.1", rand(49152:64000))
    close(tcp)
    return Int(port)
end

# ------------------------------------------------ a second stub, for 37 and 43
# Group 26 closed the first stub on purpose. This one runs the same handler on
# another spare loopback port, and is closed before the last group.
const STUB2_PORT = spare_port()
const STUB2 = Logging.with_logger(Logging.NullLogger()) do
    HTTP.serve!(stub_handler, "127.0.0.1", STUB2_PORT)
end
const STUB2_BASE = "http://127.0.0.1:$(STUB2_PORT)"
Resend.API_BASE[] = STUB2_BASE
local_only()
STUB_MODE[] = :auto

# =============================================================================
# 30. A change log that becomes unreadable after a version was handed over (F1)
# =============================================================================
println("\n30. A torn line after the report was handed over")

const SNAP30 = logsnap()
fresh_schedule!(DateTime(2032, 1, 4, 17, 30))
res = tick_at(DateTime(2032, 1, 5, 9, 0))
v30 = created()
ok("a quiet version is handed over first, with no problem recorded",
   res == [:scheduled] && get(state(), "problem", "x") == "")
n30 = nlogrows() + 1
append_raw!("2032-01-05 10:00:00,tester,sav\n")
res = tick_at(DateTime(2032, 1, 5, 10, 0, 30))
c30 = created()
ok("a torn line inside the coming stretch replaces the waiting version, though it adds no row",
   res == [:scheduled, :cancelled] && c30.id != v30.id && last_cancel() == v30.id)
ok("the new version's subject says the change log could not be read",
   subject_of(c30) == "ldgr: CHANGE LOG COULD NOT BE READ — report for 5 January 2032")
ok("and its body opens with that, naming the row, before the heading",
   startswith(lead_para(body_of(c30)), "THE CHANGE LOG COULD NOT BE READ PROPERLY") &&
   occursin(line_prefix(n30), lead_para(body_of(c30))) &&
   before(body_of(c30), "THE CHANGE LOG COULD NOT BE READ PROPERLY", "LDGR DAILY REPORT"))
st = state()
ok("the state file records the problem the version was built with, and the same row count",
   get(st, "problem", "") == line_problem(n30) &&
   get(st, "rows", -1) == 0)
res = tick_at(DateTime(2032, 1, 5, 10, 1, 30))
ok("a minute later, with the same problem, nothing more is handed over", res == [:idle])

println("\n   The change log is mended")
write(LOGP, SNAP30)
res = tick_at(DateTime(2032, 1, 5, 10, 2, 30))
ok("a version built while the log was unreadable is replaced once it reads cleanly",
   res == [:scheduled, :cancelled] && last_cancel() == c30.id)
ok("by an ordinary quiet one",
   subject_of(created()) == "ldgr: report for 5 January 2032 — nothing to report" &&
   get(state(), "problem", "x") == "")

println("\n   A version that already said so reaches its send time")
fresh_schedule!(DateTime(2032, 1, 6, 17, 30))
append_raw!("2032-01-07 10:00:00,tester,sav\n")
res = tick_at(DateTime(2032, 1, 7, 10, 30))
ok("a version is built with the problem in it",
   res == [:scheduled] && occursin("CHANGE LOG COULD NOT BE READ", subject_of(created())))
res = tick_at(DateTime(2032, 1, 7, 17, 31))
ok("after its send time it is settled, not followed up: it already told the owner",
   res == [:settled, :scheduled] && Notify.last_reported() == DateTime(2032, 1, 7, 17, 30))
ok("the audit log says it had already said so",
   occursin("email: the report for 7 January 2032, sent by Resend at 5:30 pm, already said the " *
            "change log could not be read properly", auditlog()))
ok("the next day's version has nothing unreadable in its own stretch",
   subject_of(created()) == "ldgr: report for 8 January 2032 — nothing to report")
write(LOGP, SNAP30)

println("\n   The line is torn after the last hand-over, and nothing ticks until after 5:30 pm")
fresh_schedule!(DateTime(2032, 1, 9, 17, 30))
tick_at(DateTime(2032, 1, 10, 9, 0))
n30 = nlogrows() + 1
append_raw!("2032-01-10 12:00:00,tester,sav\n")
res = tick_at(DateTime(2032, 1, 10, 17, 31))
fu30 = created(-1)
ok("the first tick after the send time sends a follow-up at once instead of settling",
   res == [:sent, :scheduled])
ok("sent now, with a correction's kind of key",
   sched_of(fu30) === nothing && startswith(fu30.idem, "ldgr-fix-203201101730-"))
ok("its subject says the log could not be read, and does not call it a corrected report",
   subject_of(fu30) == "ldgr: CHANGE LOG COULD NOT BE READ — report for 10 January 2032")
ok("it says it follows the 5:30 pm report, and why",
   occursin("This follows the report sent at 5:30 pm. When ldgr checked it afterwards, part of the " *
            "change log for that stretch could not be read, so that report may have left an entry out.",
            flat(body_of(fu30))))
ok("and it opens by naming the row",
   occursin(line_prefix(n30), lead_para(body_of(fu30))))
ok("the marker moves to that evening", Notify.last_reported() == DateTime(2032, 1, 10, 17, 30))
ok("the audit log says a follow-up was sent, and why",
   occursin("email: a follow-up report for 10 January 2032 was sent, because part of the change log " *
            "could not be read (nothing saved in it)", auditlog()))
ok("the next day's version is an ordinary one",
   subject_of(created()) == "ldgr: report for 11 January 2032 — nothing to report")
res = tick_at(DateTime(2032, 1, 10, 17, 32))
ok("and the follow-up is not sent again", res == [:idle])
write(LOGP, SNAP30)

println("\n   A torn line and a late save in the same stretch")
fresh_schedule!(DateTime(2032, 1, 12, 17, 30))
tick_at(DateTime(2032, 1, 13, 9, 0))
append_raw!("2032-01-13 12:00:00,tester,sav\n")
logged!(DateTime(2032, 1, 13, 17, 29, 30), Date(2032, 1, 13))
res = tick_at(DateTime(2032, 1, 13, 17, 31))
fx30 = created(-1)
ok("more rows and a problem: one corrected report, which says both",
   res == [:sent, :scheduled] &&
   subject_of(fx30) == "ldgr: CHANGE LOG COULD NOT BE READ — corrected report for 13 January 2032 — 1 day entered" &&
   occursin("This replaces the report sent at 5:30 pm", flat(body_of(fx30))))
write(LOGP, SNAP30)

# =============================================================================
# 31. A last line with no newline, and an emptied change log (F2)
# =============================================================================
println("\n31. A last line with no newline, and a change log emptied to nothing")

const SNAP31 = logsnap()
n31 = nlogrows() + 1
append_raw!("2032-02-03 09:00:00,tester,sav")                 # torn, with no newline after it
logged!(DateTime(2032, 2, 3, 10, 0), Date(2032, 2, 3))
rows31, prob31 = Changes.rows_checked(DateTime(2032, 2, 2, 17, 30), DateTime(2032, 2, 3, 17, 30))
ok("a save appended after a torn last line reads back whole",
   length(rows31) == 1 && rows31[1].when == DateTime(2032, 2, 3, 10, 0) &&
   rows31[1].day == Date(2032, 2, 3) && rows31[1].what == "saved" && rows31[1].ledger == "written")
ok("the torn line stays on a line of its own, where it is named",
   prob31 == line_problem(n31) &&
   loglines()[end-1] == "2032-02-03 09:00:00,tester,sav" &&
   startswith(loglines()[end], "2032-02-03 10:00:00,"))
s31, b31 = Notify.build_digest(DateTime(2032, 2, 2, 17, 30), DateTime(2032, 2, 3, 17, 30))
ok("and the report shows the save",
   occursin("3 February 2032 — balanced.", b31) && occursin("Entered by tester at 10:00 am.", b31) &&
   occursin("1 day entered", s31))
write(LOGP, SNAP31)

logged!(DateTime(2032, 2, 5, 10, 0), Date(2032, 2, 5))
write(LOGP, rstrip(logsnap(), ['\r', '\n']))
ok("(the last row's newline is taken off)", !endswith(logsnap(), "\n"))
logged!(DateTime(2032, 2, 5, 11, 0), Date(2032, 2, 4))
rows31, prob31 = Changes.rows_checked(DateTime(2032, 2, 4, 17, 30), DateTime(2032, 2, 5, 17, 30))
ok("a complete last row whose newline was stripped, and the save after it, both read back",
   prob31 == "" && [r.day for r in rows31] == [Date(2032, 2, 5), Date(2032, 2, 4)])
write(LOGP, SNAP31)

println("\n   A change log emptied to nothing")
write(LOGP, "")
logged!(DateTime(2032, 2, 7, 10, 0), Date(2032, 2, 7))
ok("an empty change log gets its header back", startswith(logsnap(), "when,who,what,day,day kind,"))
rows31, prob31 = Changes.rows_checked(nothing, DateTime(2100, 1, 1))
ok("and the row under it reads", length(rows31) == 1 && prob31 == "" && rows31[1].day == Date(2032, 2, 7))
write(LOGP, SNAP31)

println("\n   A real save, after a torn last line")
const TORN31 = "2032-02-09 09:00:00,tester,sav"
append_raw!(TORN31)
t31 = floor(now(), Second) - Second(1)
o31 = Chain.saved_record(Date(2026, 2, 12)).amounts[:closing_balance]
rs31 = save(day(Date(2026, 2, 13); o = o31, c = o31))
r31 = last_row(Date(2026, 2, 13))
ok("a day saves through process_day and after_save", rs31.out.ok && r31 !== nothing && text(r31.what) == "saved")
s31, b31 = digest(t31)
ok("its row reads back, and the report shows it with no complaint about this stretch",
   occursin("13 February 2026 — balanced.", section(b31, "DAYS ENTERED")) &&
   !occursin("CHANGE LOG COULD NOT BE READ", s31))
write(LOGP, join(filter(l -> rstrip(l, '\r') != TORN31, split(logsnap(), '\n')), '\n'))
ok("the torn line is taken out again, and the log reads cleanly",
   !occursin(TORN31, logsnap()) && Changes.rows_checked(nothing, DateTime(2100, 1, 1))[2] == "" &&
   last_row(Date(2026, 2, 13)) !== nothing)

# =============================================================================
# 32. Two rows run together on one line (F3)
# =============================================================================
println("\n32. Two rows run together on one line")

# WHERE THE LINE SITS MATTERS, because of CSV.jl. Reading with `types = String`,
# CSV.jl 0.10.16 sizes a column that first appears on a too-long line from its
# ORIGINAL guess of the row count, then writes that line's cell at its real row
# number. A too-long line past the guess — the last line, where a torn line and
# the save appended to it end up — is written past the end of the column: the
# cell reads back as `missing`, and the stray write can bring Julia down with an
# access violation. And a malformed line among the first ten that CSV.jl reads
# to guess the delimiter can make it choose ':' (from the times) over ','. So
# the line is first put in the middle of the log, past both, where this file's
# own rule is what is tested; then at the bottom, in a separate Julia process,
# so that a crash fails a check instead of ending this run.
const SNAP32 = logsnap()
const JOINED32 = "2032-03-01 10:00:00,tester,sav" * rawrow("2032-03-05 10:00:00", "2032-03-05")
readable32 = length(Changes._read_log())
insert_row!(JOINED32, 15)
rows32, prob32 = Changes.rows_checked(DateTime(2032, 3, 4, 17, 30), DateTime(2032, 3, 5, 17, 30))
ok("a line holding two rows, dated in an older stretch, counts against the current one too",
   isempty(rows32) && !isempty(prob32))
s32, b32 = Notify.build_digest(DateTime(2032, 3, 4, 17, 30), DateTime(2032, 3, 5, 17, 30))
ok("so the current report says the log could not be read instead of giving an all-clear",
   occursin("CHANGE LOG COULD NOT BE READ", s32) && !occursin("Nothing was entered or changed", b32))
ok("and so does a report years later",
   !isempty(Changes.rows_checked(DateTime(2040, 1, 1, 17, 30), DateTime(2040, 1, 2, 17, 30))[2]))
ok("every other row still reads", length(Changes._read_log()) == readable32)
write(LOGP, SNAP32)
insert_row!(JOINED32, 2)
ok("near the top of the log, among the lines CSV.jl reads to guess the delimiter, it still costs only that line",
   length(Changes._read_log()) == readable32)
write(LOGP, SNAP32)
ok("with the line taken out, the current stretch is clean again",
   Changes.rows_checked(DateTime(2032, 3, 4, 17, 30), DateTime(2032, 3, 5, 17, 30))[2] == "")

println("\n   The same line as the last line of the log, read in a separate process")
code32, out32 = in_child("""
    rows, prob = Changes.rows_checked(DateTime(2032, 3, 4, 17, 30), DateTime(2032, 3, 5, 17, 30))
    s, b = Notify.build_digest(DateTime(2032, 3, 4, 17, 30), DateTime(2032, 3, 5, 17, 30))
    println("RESULT problem=", !isempty(prob))
    println("RESULT subject=", occursin("CHANGE LOG COULD NOT BE READ", s))
    GC.gc(true); GC.gc(true)
    println("RESULT survived=true")
    """, SNAP32 * JOINED32 * "\n")
ok("as the LAST line, the current stretch is flagged too",
   child_result(out32, "problem") == "true" && child_result(out32, "subject") == "true")
ok("and reading it does not bring the process down", code32 == 0 && child_result(out32, "survived") == "true")
if !(code32 == 0 && child_result(out32, "problem") == "true")
    crash32 = something(match(r"Exception: [^\n]{0,90}", out32), (match = "",)).match
    println("      -> the separate process exited with $(code32) and answered: problem=",
            repr(child_result(out32, "problem")), ", survived=", repr(child_result(out32, "survived")),
            isempty(crash32) ? "" : "; it said: " * crash32)
end

# =============================================================================
# 33. A row cut short, and flags as a spreadsheet saves them (F4)
# =============================================================================
println("\n33. A row cut short, and TRUE/FALSE flags")

const SNAP33 = logsnap()
n33 = nlogrows() + 1
append_raw!("2032-09-02 10:00:00,tester,saved,2032-09-02,trading,added\n")
rows33, prob33 = Changes.rows_checked(DateTime(2032, 9, 1, 17, 30), DateTime(2032, 9, 2, 17, 30))
ok("a row cut off after its journal cell is skipped and named, not read as a day",
   isempty(rows33) && prob33 == line_problem(n33))
s33, b33 = Notify.build_digest(DateTime(2032, 9, 1, 17, 30), DateTime(2032, 9, 2, 17, 30))
ok("the report says the log could not be read, and never that the day balanced",
   occursin("CHANGE LOG COULD NOT BE READ", s33) && !occursin("2 September 2032 — balanced.", b33))
write(LOGP, SNAP33)

append_raw!(rawrow("2032-09-03 09:00:00", "2032-09-01"; what = "edited",
                   flags = ("TRUE", "FALSE", "FALSE", "FALSE"),
                   changed = "Cash Sales \$0.00 -> \$500.00") * "\n")
rows33, prob33 = Changes.rows_checked(DateTime(2032, 9, 2, 17, 30), DateTime(2032, 9, 3, 17, 30))
ok("TRUE and FALSE in capitals, as a spreadsheet saves them, still read",
   length(rows33) == 1 && prob33 == "" && rows33[1].cross_day_edit === true &&
   rows33[1].pending_day === false && rows33[1].now_balances === false)
s33, b33 = Notify.build_digest(DateTime(2032, 9, 2, 17, 30), DateTime(2032, 9, 3, 17, 30))
ok("and that edit is reported as a later-date edit",
   occursin("Changed on 3 September 2032 by tester at 9:00 am:", section(b33, "CHANGES TO DAYS ALREADY SAVED")))
write(LOGP, SNAP33)

append_raw!(rawrow("2032-09-04 09:00:00", "2032-09-04"; flags = ("maybe", "false", "false", "false")) * "\n")
rows33, prob33 = Changes.rows_checked(DateTime(2032, 9, 3, 17, 30), DateTime(2032, 9, 4, 17, 30))
ok("a flag that is neither true nor false makes the row unreadable, not a day with no flags",
   isempty(rows33) && !isempty(prob33))
write(LOGP, SNAP33)

# =============================================================================
# 34. What the change log reader says in the terminal (F5)
# =============================================================================
println("\n34. Warnings from reading the change log")

const SNAP34 = logsnap()
append_raw!("2032-09-10 10:00:00,tester,sav\n")                                              # too few cells
# Too many cells — in the middle of the log, for the reasons given in group 32.
insert_row!("2032-09-11 10:00:00,tester,sav" * rawrow("2032-09-12 10:00:00", "2032-09-12"), 15)
const CAP34 = Capture(Any[])
Logging.with_logger(CAP34) do
    for _ in 1:3
        Changes.rows_checked(DateTime(2032, 9, 9, 17, 30), DateTime(2032, 9, 12, 17, 30))
    end
end
ok("CSV.jl's own warnings about short and long lines are silenced ($(length(CAP34.recs)) records seen)",
   !any(r -> occursin("CSV", r.mod) || occursin("columns around data row", r.msg), CAP34.recs))
skips34 = filter(r -> occursin("could not be read and was skipped", r.msg), CAP34.recs)
ok("ldgr's own warning for a skipped line asks to be shown once (maxlog = 1)",
   !isempty(skips34) && all(r -> get(r.kw, :maxlog, nothing) == 1, skips34))
write(LOGP, SNAP34)

# =============================================================================
# 35. Every reported edit, with who made it and when (F6)
# =============================================================================
println("\n35. Every reported edit, with who made it and when")

logrow!(DateTime(2032, 10, 1, 10, 0), Date(2032, 10, 1))
logrow!(DateTime(2032, 10, 3, 9, 0), Date(2032, 10, 1); what = "edited", who = "alice", cross = true,
        changed = "Closing Balance \$1,000.00 -> \$1,200.00")
logrow!(DateTime(2032, 10, 3, 11, 0), Date(2032, 10, 1); what = "edited", who = "bob", cross = true,
        changed = "Closing Balance \$1,200.00 -> \$1,500.00")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 2, 17, 30), DateTime(2032, 10, 3, 17, 30))
blk35 = block(section(b35, "CHANGES TO DAYS ALREADY SAVED"), "1 October 2032 was changed")
ok("two later-date edits of one day in one report: told once, under changes",
   startswith(blk35, "1 October 2032 was changed on 3 October 2032.") &&
   occursin("   It was first saved on 1 October 2032.", blk35))
ok("the first edit is shown, with who and when, and the figure it started from",
   occursin("   Changed on 3 October 2032 by alice at 9:00 am:\n" *
            "      Closing Balance \$1,000.00 -> \$1,200.00", blk35))
ok("and the second after it",
   occursin("   Changed on 3 October 2032 by bob at 11:00 am:\n" *
            "      Closing Balance \$1,200.00 -> \$1,500.00", blk35))
ok("with no single 'Changed by' line standing for both", !occursin("Changed by", blk35))

logrow!(DateTime(2032, 10, 5, 10, 0), Date(2032, 10, 5))
logrow!(DateTime(2032, 10, 7, 9, 0), Date(2032, 10, 5); what = "edited", cross = true,
        changed = "Cash Sales \$0.00 -> \$500.00")
logrow!(DateTime(2032, 10, 7, 9, 5), Date(2032, 10, 5); what = "edited", cross = true, changed = "")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 6, 17, 30), DateTime(2032, 10, 7, 17, 30))
blk35 = block(section(b35, "CHANGES TO DAYS ALREADY SAVED"), "5 October 2032 was changed")
ok("a later save with nothing different does not hide the edit before it",
   occursin("   Changed on 7 October 2032 by tester at 9:00 am:\n      Cash Sales \$0.00 -> \$500.00", blk35))
ok("it is shown as a save with no figure different",
   occursin("   Changed on 7 October 2032 by tester at 9:05 am, with no figure different.", blk35))

println("\n   Under GAPS FILLED")
logrow!(DateTime(2032, 10, 12, 18, 0), Date(2032, 10, 11); gap = true)
logrow!(DateTime(2032, 10, 13, 9, 0), Date(2032, 10, 11); what = "edited", cross = true,
        changed = "Closing Balance \$2,000.00 -> \$2,100.00")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 12, 17, 30), DateTime(2032, 10, 13, 17, 30))
gblk35 = block(section(b35, "GAPS FILLED, AND THE LEDGERS THEY RELEASED"),
               "11 October 2032 was entered on 12 October 2032")
ok("a gap filled after the send time and edited the next morning is spelled out under the gaps",
   occursin("   Entered by tester at 6:00 pm.\n" *
            "   Changed on 13 October 2032 by tester at 9:00 am:\n" *
            "      Closing Balance \$2,000.00 -> \$2,100.00", gblk35))
ok("not as a bare 'Changed again', and not a second time under days entered",
   !occursin("Changed again", gblk35) && !has_section(b35, "DAYS ENTERED"))

logrow!(DateTime(2032, 10, 16, 9, 0), Date(2032, 10, 14); gap = true, ledger = "held")
logrow!(DateTime(2032, 10, 16, 9, 30), Date(2032, 10, 14); what = "edited", pending = true, ledger = "held",
        changed = "Cash Sales \$0.00 -> \$300.00")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 15, 17, 30), DateTime(2032, 10, 16, 17, 30))
gblk35 = block(section(b35, "GAPS FILLED, AND THE LEDGERS THEY RELEASED"),
               "14 October 2032 was entered on 16 October 2032")
ok("a gap day edited the same date while its own ledger waits says why that edit is told",
   occursin("   Entered by tester at 9:00 am.\n" *
            "   Its ledger had not been made yet — it was waiting on the day before it.\n" *
            "   Changed on 16 October 2032 by tester at 9:30 am:\n" *
            "      Cash Sales \$0.00 -> \$300.00", gblk35))

println("\n   Under DAYS ENTERED")
logrow!(DateTime(2032, 10, 20, 18, 0), Date(2032, 10, 20); day_diff = -400.0, reason = "Could not find")
logrow!(DateTime(2032, 10, 20, 18, 20), Date(2032, 10, 20); what = "edited", day_diff = -400.0,
        reason = "Could not locate", was_day = -400.0, was_night = 0.0,
        changed = "Reason \"Could not find\" -> \"Could not locate\"")
logrow!(DateTime(2032, 10, 21, 9, 0), Date(2032, 10, 20); what = "edited", cross = true, balances = true,
        day_diff = 0.0, was_day = -400.0, was_night = 0.0,
        changed = "Closing Balance \$1,600.00 -> \$2,000.00; Reason \"Could not locate\" -> \"\"")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 20, 17, 30), DateTime(2032, 10, 21, 17, 30))
eblk35 = block(section(b35, "DAYS ENTERED"), "20 October 2032 —")
ok("the next-morning edit that made a day balance: the day is entered, and balanced",
   startswith(eblk35, "20 October 2032 — balanced.") && occursin("   Entered by tester at 6:00 pm.", eblk35))
ok("the edit is spelled out, each figure on its own line",
   occursin("   Changed on 21 October 2032 by tester at 9:00 am:\n" *
            "      Closing Balance \$1,600.00 -> \$2,000.00\n" *
            "      Reason \"Could not locate\" -> \"\"", eblk35))
ok("then what the difference was, and that it balances now",
   occursin("   It did not balance before: shortage of \$400.00 during the day.\n   It balances now.", eblk35))
ok("the same-evening correction before it stays folded away",
   !occursin("6:20 pm", eblk35) && !occursin("Changed again", eblk35))

logrow!(DateTime(2032, 10, 23, 9, 0), Date(2032, 10, 23))
logrow!(DateTime(2032, 10, 23, 10, 0), Date(2032, 10, 23); what = "edited", who = "carol",
        changed = "Cash Sales \$0.00 -> \$100.00")
s35, b35 = Notify.build_digest(DateTime(2032, 10, 22, 17, 30), DateTime(2032, 10, 23, 17, 30))
fblk35 = block(section(b35, "DAYS ENTERED"), "23 October 2032 —")
ok("an ordinary same-date correction is still the one line it always was",
   occursin("   Changed again by carol at 10:00 am.", fblk35) && !occursin("Changed on", fblk35))

# =============================================================================
# 36. A report whose only rows are same-date corrections (F7)
# =============================================================================
println("\n36. Only same-date corrections")

logrow!(DateTime(2032, 11, 3, 17, 0), Date(2032, 11, 3))
logrow!(DateTime(2032, 11, 3, 18, 0), Date(2032, 11, 3); what = "edited",
        changed = "Cash Sales \$0.00 -> \$200.00")
s36, b36 = Notify.build_digest(DateTime(2032, 11, 3, 17, 30), DateTime(2032, 11, 4, 17, 30))
ok("a same-date correction made after the report that showed the day: no section at all",
   !any(h -> has_section(b36, h), HEADINGS))
ok("and not the sentence that says nothing was changed", !occursin("Nothing was entered or changed", b36))
ok("instead it says the only changes were same-date corrections",
   occursin("Nothing new was entered, and every recorded day has its ledger. The only changes were " *
            "corrections made on the same date a day was first typed in, which are not reported one by one.",
            flat(b36)))
ok("with how current it is", occursin("Includes everything saved up to 6:00 pm on 3 November.", b36))
ok("and a subject that still says there is nothing to report",
   s36 == "ldgr: report for 4 November 2032 — nothing to report")
s36, b36 = Notify.build_digest(DateTime(2032, 11, 4, 17, 30), DateTime(2032, 11, 5, 17, 30))
ok("an empty stretch still gives the exact quiet sentence",
   occursin("Nothing was entered or changed today, and every recorded day has its ledger.", b36) &&
   !occursin("Nothing new was entered", b36))

# =============================================================================
# 37. A hand-over whose answer was lost (F9)
# =============================================================================
println("\n37. A hand-over whose answer was lost")

const STATE_FIELDS = Set(["id", "cutoff", "from", "rows", "generation", "settings", "cancel", "problem"])
const PENDING_FIELDS = Set(["kind", "key", "from", "cutoff", "rows", "problem", "generation",
                            "settings", "written", "email"])
const REFUSE_KEY = Ref("")
refusing_send(key, email, idem) =
    String(idem) == REFUSE_KEY[] ?
        throw(Resend.Failure(:settings, "Resend refused the report (422). Check `to` and `from` in " *
                                        "notify.toml. (test: refused on replay)")) :
        fake_send(key, email, idem)
const REFUSING = (send = refusing_send, cancel = fake_cancel)

println("\n   Lost, then another save")
fresh_schedule!(DateTime(2032, 12, 1, 17, 30))
tick_at(DateTime(2032, 12, 2, 9, 0))
v37 = created().id
logged!(DateTime(2032, 12, 2, 10, 0), Date(2032, 12, 2))
LOSE_REPLY[] = true
res = tick_at(DateTime(2032, 12, 2, 10, 0, 30))
lost37 = created()
st = state()
pq = pending_of(st)
ok("Resend made the email but the answer was lost: the hand-over counts as failed",
   res == [:failed] && lost37.id != v37)
ok("the state file still names the older version as the one waiting", get(st, "id", "") == v37)
ok("and holds the unanswered hand-over, as it was sent",
   get(pq, "kind", "") == "scheduled" && get(pq, "key", "") == lost37.idem &&
   get(get(pq, "email", Dict()), "subject", "") == subject_of(lost37) &&
   get(get(pq, "email", Dict()), "text", "") == body_of(lost37) &&
   get(get(pq, "email", Dict()), "scheduled_at", "") == sched_of(lost37) &&
   get(get(pq, "email", Dict()), "to", Any[]) == lost37.email["to"] &&
   get(pq, "rows", -1) == 1 && get(pq, "written", "") == "2032-12-02 10:00:30")
ok("the state file holds exactly the agreed fields, and 'pending' while a hand-over is unconfirmed",
   Set(keys(st)) == union(STATE_FIELDS, Set(["pending"])) && Set(keys(pq)) == PENDING_FIELDS &&
   Set(keys(get(pq, "email", Dict()))) == Set(["from", "to", "subject", "text", "html", "scheduled_at"]))
ok("the API key is not in it", !occursin(KEY, read(statefile(), String)))
logged!(DateTime(2032, 12, 2, 10, 10), Date(2032, 12, 1))
res = tick_at(DateTime(2032, 12, 2, 10, 10, 30); poked = true)
ok("the next tick asks again with the same key before building anything, adopts it, then replaces it",
   res == [:scheduled, :cancelled, :scheduled, :cancelled])
ok("in that order: the repeat, the oldest cancelled, the new version, the adopted one cancelled",
   length(CREATES) == 4 &&
   EVENTS == ["create:$(v37)", "create:$(lost37.id)", "create:$(lost37.id)", "cancel:$(v37)",
              "create:$(created().id)", "cancel:$(lost37.id)"] &&
   CREATES[3].idem == lost37.idem)
ok("so only ONE email is left waiting at Resend",
   live_ids() == [created().id] && get(state(), "id", "") == created().id)
ok("the hand-over is cleared and nothing is left to cancel",
   !haskey(state(), "pending") && isempty(leftovers()) && Set(keys(state())) == STATE_FIELDS)

println("\n   Lost, and the repeat cannot get through either")
fresh_schedule!(DateTime(2032, 12, 3, 17, 30))
tick_at(DateTime(2032, 12, 4, 9, 0))
logged!(DateTime(2032, 12, 4, 10, 0), Date(2032, 12, 4))
LOSE_REPLY[] = true
tick_at(DateTime(2032, 12, 4, 10, 0, 30))
key37 = created().idem
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: repeat outage)")
t0 = SEND_TRIES[]; c0 = CANCEL_TRIES[]
res = tick_at(DateTime(2032, 12, 4, 10, 6))
ok("the repeat fails: the tick stops there and tries nothing else",
   res == [:failed] && SEND_TRIES[] == t0 + 1 && CANCEL_TRIES[] == c0)
ok("the hand-over is kept for next time", get(pending_of(state()), "key", "") == key37)
ok("and a five-minute pause starts",
   Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].kind === :temporary &&
   Notify.BACKOFF[].until == DateTime(2032, 12, 4, 10, 11))
SEND_FAIL[] = nothing
res = tick_at(DateTime(2032, 12, 4, 10, 12))
ok("when Resend answers, the repeat is adopted and the older version cancelled",
   res == [:scheduled, :cancelled] && !haskey(state(), "pending") && created().idem == key37)

println("\n   Lost, and ldgr is next opened after 5:30 pm")
fresh_schedule!(DateTime(2032, 12, 5, 17, 30))
logged!(DateTime(2032, 12, 6, 10, 0), Date(2032, 12, 6))
LOSE_REPLY[] = true
res = tick_at(DateTime(2032, 12, 6, 10, 0, 30))
ok("the only version's answer is lost", res == [:failed] && get(state(), "id", "x") == "")
n37 = length(CREATES)
res = tick_at(DateTime(2032, 12, 6, 17, 31))
ok("a version whose send time has come is not asked about again: nothing goes with a send time in the past",
   res == [:late, :scheduled] && !any(c -> sched_of(c) !== nothing &&
       sched_of(c) <= Notify._utc_text(DateTime(2032, 12, 6, 17, 31)), CREATES[n37+1:end]))
late37 = [c for c in CREATES[n37+1:end] if startswith(c.idem, "ldgr-late-")]
ok("what it held goes out as one late report, which says it may repeat the 5:30 pm one",
   length(late37) == 1 &&
   occursin("This report may repeat one sent at 5:30 pm: ldgr could not confirm that Resend had " *
            "received it before ldgr was closed or went offline. If both arrived, this one is complete.",
            flat(body_of(late37[1]))))
ok("the audit log says the version could not be confirmed",
   occursin("email: whether Resend received the version of the report for 6 December 2032 could not " *
            "be confirmed before 5:30 pm", auditlog()))
ok("and the marker is at that evening", Notify.last_reported() == DateTime(2032, 12, 6, 17, 30))

println("\n   Lost, and not asked about for more than 23 hours")
fresh_schedule!(DateTime(2032, 12, 7, 17, 30))
logged!(DateTime(2032, 12, 8, 10, 0), Date(2032, 12, 8))
LOSE_REPLY[] = true
tick_at(DateTime(2032, 12, 8, 10, 0, 30))
keyc37 = created().idem
res = tick_at(DateTime(2032, 12, 9, 9, 1))
ok("a hand-over unanswered for more than 23 hours is not asked about again",
   count(c -> c.idem == keyc37, CREATES) == 1)
ok("it is dropped, with a line in the audit log",
   !haskey(state(), "pending") &&
   occursin("email: whether Resend received the version of the report for 8 December 2032 could not " *
            "be confirmed before 5:30 pm, so what it held is sent again as a corrected or late report; " *
            "if two reports arrive for that day, the one that includes the later entries is the right one",
            auditlog()))
ok("and the stretch goes out as a late report", res == [:late, :scheduled])

println("\n   Lost, and Resend refuses the repeat")
fresh_schedule!(DateTime(2032, 12, 10, 17, 30))
tick_at(DateTime(2032, 12, 11, 9, 0))
logged!(DateTime(2032, 12, 11, 10, 0), Date(2032, 12, 11))
LOSE_REPLY[] = true
tick_at(DateTime(2032, 12, 11, 10, 0, 30))
REFUSE_KEY[] = created().idem
# Another save before the repeat, so the version built after the refusal is
# different from the refused one (the same content would carry the same key
# and be refused the same way).
logged!(DateTime(2032, 12, 11, 10, 30), Date(2032, 12, 11))
Notify.MAILER[] = REFUSING
res = tick_at(DateTime(2032, 12, 11, 17, 20))
ok("a refused repeat is dropped, and the save it held is handed over in a new version",
   res == [:scheduled, :cancelled] && !haskey(state(), "pending"))
ok("the audit log says it was refused and not made, and why",
   occursin("email: the report for 11 December 2032 was refused when it was asked about again, so it " *
            "was not made", auditlog()) && occursin("(test: refused on replay)", auditlog()))
ok("no hour-long pause starts", Notify.BACKOFF[] === nothing || Notify.BACKOFF[].kind !== :settings)
res = tick_at(DateTime(2032, 12, 11, 17, 31))
ok("so the evening settles as usual", res == [:settled, :scheduled])
Notify.MAILER[] = FAKE
REFUSE_KEY[] = ""

println("\n   Refused the first time")
fresh_schedule!(DateTime(2032, 12, 12, 17, 30))
SEND_FAIL[] = Resend.Failure(:settings, OWN)
res = tick_at(DateTime(2032, 12, 13, 9, 0))
ok("a hand-over Resend refused leaves nothing pending: nothing was made",
   res == [:failed] && isfile(statefile()) && !haskey(state(), "pending"))
SEND_FAIL[] = nothing

println("\n   The hand-over is asked about again word for word")
const FUNNY = "Counted twice: \"float\" \\ till\tdrawer — café ✓"
fresh_schedule!(DateTime(2032, 12, 14, 17, 30))
logrow!(DateTime(2032, 12, 15, 10, 0), Date(2032, 12, 15); day_diff = -5.0, reason = FUNNY)
LOSE_REPLY[] = true
tick_at(DateTime(2032, 12, 15, 10, 0, 30))
orig37 = created()
ok("(the email holds quotes, a backslash, a tab and letters beyond ASCII)",
   occursin(FUNNY, body_of(orig37)) && occursin('\\', body_of(orig37)))
ok("the state file keeps its text exactly",
   get(get(pending_of(state()), "email", Dict()), "text", "") == body_of(orig37))
# A save after the lost answer: a report rebuilt from the books now would differ,
# so only a repeat read back from the state file can match the first request.
logged!(DateTime(2032, 12, 15, 10, 3), Date(2032, 12, 14))
res = tick_at(DateTime(2032, 12, 15, 10, 6))
rep37 = length(CREATES) >= 2 ? CREATES[2] : NONE
ok("the repeat is the email first sent, byte for byte, with the same key, though the books have moved on",
   rep37.idem == orig37.idem && JSON3.write(rep37.email) == JSON3.write(orig37.email))
ok("and the save made since goes out in a new version, which replaces it",
   res == [:scheduled, :scheduled, :cancelled] && length(CREATES) == 3 &&
   subject_of(created()) != subject_of(orig37) && last_cancel() == orig37.id)

fresh_schedule!(DateTime(2032, 12, 16, 17, 30))
logrow!(DateTime(2032, 12, 17, 10, 0), Date(2032, 12, 17); day_diff = -5.0, reason = FUNNY)
Resend.API_BASE[] = STUB2_BASE
local_only()
Notify.MAILER[] = (send   = (key, email, idem) -> Resend.send(key, email; idempotency_key = idem),
                   cancel = Resend.cancel)
STUB_MODE[] = (500, "{\"statusCode\":500,\"name\":\"application_error\",\"message\":\"test\"}", 0.0)
empty!(STUB_HITS)
res = tick_at(DateTime(2032, 12, 17, 10, 0, 30))
ok("through Resend.jl: a 500 keeps the hand-over to ask again", res == [:failed] && haskey(state(), "pending"))
logged!(DateTime(2032, 12, 17, 10, 3), Date(2032, 12, 16))
STUB_MODE[] = :auto
res = tick_at(DateTime(2032, 12, 17, 10, 6))
ok("the repeat is handed over, then the version with the later save, and the repeat is cancelled",
   res == [:scheduled, :scheduled, :cancelled] && length(STUB_HITS) == 4 &&
   STUB_HITS[3].target == "/emails" && endswith(STUB_HITS[4].target, "/cancel"))
h1 = length(STUB_HITS) >= 1 ? STUB_HITS[1] : (headers = Dict{String,String}(), body = "1")
h2 = length(STUB_HITS) >= 2 ? STUB_HITS[2] : (headers = Dict{String,String}(), body = "2")
ok("the first request and its repeat carried the same JSON, byte for byte, and the same idempotency key",
   h1.body == h2.body && !isempty(get(h1.headers, "idempotency-key", "")) &&
   get(h1.headers, "idempotency-key", "") == get(h2.headers, "idempotency-key", ""))
ok("and the text arrived intact",
   (jb37 = try JSON3.read(h2.body) catch; nothing end; jb37 !== nothing && occursin(FUNNY, String(jb37.text))))
Notify.MAILER[] = FAKE

println("\n   A late report whose answer is lost")
fresh_schedule!(DateTime(2032, 12, 18, 17, 30))
logged!(DateTime(2032, 12, 19, 10, 0), Date(2032, 12, 19))
LOSE_REPLY[] = true
res = tick_at(DateTime(2032, 12, 20, 9, 0))
late37 = created()
ok("its hand-over is written down as a late one",
   res == [:failed] && startswith(late37.idem, "ldgr-late-203212191730-") &&
   get(pending_of(state()), "kind", "") == "late")
res = tick_at(DateTime(2032, 12, 20, 17, 31))
lates37 = [c for c in CREATES if startswith(c.idem, "ldgr-late-")]
ok("after the next send time it is asked about again, not rebuilt over a longer stretch",
   res == [:late, :scheduled] && length(unique([c.id for c in lates37])) == 1 &&
   all(c -> c.idem == late37.idem, lates37))
ok("the marker moves to its own cutoff", Notify.last_reported() == DateTime(2032, 12, 19, 17, 30))
ok("the audit log says it was confirmed",
   occursin("email: a late report covering 19 December 2032 was sent (confirmed when it was asked " *
            "about again)", auditlog()))
ok("and the coming report picks up from there",
   occursin("covering 19 December 5:30 pm to 21 December 5:30 pm", body_of(created())))

println("\n   A correction whose answer is lost")
fresh_schedule!(DateTime(2032, 12, 22, 17, 30))
tick_at(DateTime(2032, 12, 23, 9, 0))
logged!(DateTime(2032, 12, 23, 17, 29, 10), Date(2032, 12, 23))
LOSE_REPLY[] = true
res = tick_at(DateTime(2032, 12, 23, 17, 31))
ok("the correction's answer is lost", res == [:failed] && startswith(created().idem, "ldgr-fix-"))
res = tick_at(DateTime(2032, 12, 23, 17, 37))
fixes37 = [c for c in CREATES if startswith(c.idem, "ldgr-fix-")]
ok("it is confirmed, not sent a second time", res == [:sent, :scheduled] &&
   length(unique([c.id for c in fixes37])) == 1)
ok("the marker moves, and the version it corrected no longer counts as waiting",
   Notify.last_reported() == DateTime(2032, 12, 23, 17, 30) &&
   get(state(), "cutoff", "") == "2032-12-24 17:30:00" && !haskey(state(), "pending"))

# =============================================================================
# 38. The two state files are replaced in one step (F10)
# =============================================================================
println("\n38. Writing the marker and the state file")

fresh_schedule!(nothing)
Notify.mark_reported!(DateTime(2032, 4, 1, 17, 30))
Notify.mark_reported!(DateTime(2032, 4, 2, 17, 30))
ok("writing the marker again replaces it",
   read(Layout.digest_marker_path(), String) == "2032-04-02 17:30:00" &&
   Notify.last_reported() == DateTime(2032, 4, 2, 17, 30))
sA38 = Notify.Scheduled(("id-A", DateTime(2032, 4, 3, 17, 30), DateTime(2032, 4, 2, 17, 30), 1, 7,
                         Notify.Leftover[], "fpA", "", nothing, nothing))
sB38 = Notify.Scheduled(("id-B", DateTime(2032, 4, 3, 17, 30), DateTime(2032, 4, 2, 17, 30), 2, 8,
                         Notify.Leftover[(id = "id-A", cutoff = DateTime(2032, 4, 3, 17, 30))], "fpA",
                         line_problem(9), nothing, nothing))
Notify._save_state(sA38)
Notify._save_state(sB38)
ok("writing the state file again replaces it, problem and all", Notify._read_state() == sB38)
ok("and neither leaves a temporary file behind",
   !any(f -> endswith(f, ".tmp"), readdir(Layout.notifications_dir())))
if Sys.iswindows()
    mp38 = Layout.digest_marker_path()
    chmod(mp38, 0o444)
    threw38 = try
        Notify.mark_reported!(DateTime(2032, 4, 3, 17, 30))
        false
    catch
        true
    end
    ok("a marker that cannot be replaced (here, made read-only) is left whole, and the failure is not hidden",
       threw38 && read(mp38, String) == "2032-04-02 17:30:00")
    chmod(mp38, 0o666)
    rm(Layout.temp_path(mp38); force = true)
else
    println("      (the read-only check is for Windows, where a rename cannot replace a read-only file)")
end

# =============================================================================
# 39. A key that can only send, over an evening of saves (F11)
# =============================================================================
println("\n39. A key that can only send, over an evening of saves")

fresh_schedule!(DateTime(2032, 5, 10, 17, 30))
tick_at(DateTime(2032, 5, 11, 9, 0))
CANCEL_FAIL[] = Resend.Failure(:settings, FULL)
a0 = count_of("email: " * FULL, auditlog())
res39 = Any[]
for m in (0, 10, 20, 30)
    logged!(DateTime(2032, 5, 11, 10, m), Date(2032, 5, 11) - Day(m ÷ 10))
    push!(res39, tick_at(DateTime(2032, 5, 11, 10, m, 30)))
end
ok("four saves in forty minutes are each handed over, though no cancel works",
   all(r -> r == [:scheduled], res39) && length(leftovers()) == 4)
ok("the 'can only send' sentence is written to the audit log once, not four times",
   count_of("email: " * FULL, auditlog()) == a0 + 1)
CANCEL_FAIL[] = nothing
logged!(DateTime(2032, 5, 11, 10, 40), Date(2032, 5, 6))
res = tick_at(DateTime(2032, 5, 11, 10, 40, 30))
ok("with a key that can cancel, all five earlier versions are cancelled",
   !isempty(res) && res[1] == :scheduled && count(==(:cancelled), res) == 5 && isempty(leftovers()))
ok("and a cancel that works makes the next failure news again",
   Notify.LAST_CANCEL_TROUBLE[] == ("", DateTime(0)) && Notify.CANCEL_BACKOFF[] === nothing)
CANCEL_FAIL[] = Resend.Failure(:settings, FULL)
logged!(DateTime(2032, 5, 11, 10, 50), Date(2032, 5, 5))
tick_at(DateTime(2032, 5, 11, 10, 50, 30))
ok("so the sentence is written again", count_of("email: " * FULL, auditlog()) == a0 + 2)
CANCEL_FAIL[] = nothing

# =============================================================================
# 40. A send time is over only when its whole second is (F12)
# =============================================================================
println("\n40. The send time's own second")

const CUT40 = DateTime(2032, 6, 3, 17, 30)
fresh_schedule!(DateTime(2032, 6, 2, 17, 30))
tick_at(DateTime(2032, 6, 3, 9, 0))
v40 = created().id
n0 = length(CREATES)
res = tick_at(CUT40 + Millisecond(200))
ok("a tick at 5:30:00.2 pm does not settle the 5:30 pm version yet",
   res == [:idle] && length(CREATES) == n0 && get(state(), "id", "") == v40 &&
   Notify.last_reported() == DateTime(2032, 6, 2, 17, 30))
res = tick_at(CUT40 + Millisecond(900))
ok("nor does one at 5:30:00.9 pm", res == [:idle] && length(CREATES) == n0)
logged!(CUT40, Date(2032, 6, 3))
res = tick_at(CUT40 + Millisecond(1100))
fx40 = created(-1)
ok("a save stamped 5:30:00 pm belongs to the 5:30 pm report: the next tick sends a correction with it",
   res == [:sent, :scheduled] && startswith(fx40.idem, "ldgr-fix-203206031730-") &&
   occursin("Includes everything saved up to 5:30 pm on 3 June.", body_of(fx40)))
ok("and the marker moves to 5:30 pm", Notify.last_reported() == CUT40)
nxt40 = created()
n0 = length(CREATES)
res = tick_at(DateTime(2032, 6, 3, 17, 25))
ok("a clock stepped back across the send time hands nothing over for the 5:30 pm already settled",
   res == [:idle] && length(CREATES) == n0 && get(state(), "id", "") == nxt40.id &&
   get(state(), "cutoff", "") == "2032-06-04 17:30:00")
res = tick_at(DateTime(2032, 6, 3, 17, 27))
ok("nor does the next tick while the clock is still behind", res == [:idle] && length(CREATES) == n0)

println("\n   A report on request, to the whole second")
fresh_schedule!(DateTime(2032, 6, 5, 17, 30))
logged!(DateTime(2032, 6, 6, 11, 0, 0), Date(2032, 6, 6))
res = tick_at(DateTime(2032, 6, 6, 11, 0, 0, 700); force = true)
nowr40 = created(-1)
ok("a forced report at 11:00:00.7 am includes the save stamped 11:00:00",
   res == [:sent, :scheduled] && occursin("6 June 2032 — balanced.", body_of(nowr40)))
ok("and the marker is that whole second", Notify.last_reported() == DateTime(2032, 6, 6, 11, 0, 0))
ok("the fresh version starts there and does not repeat the save",
   get(state(), "from", "") == "2032-06-06 11:00:00" && get(state(), "rows", -1) == 0)

# =============================================================================
# 41. The clock is read once the tick has the lock (F13)
# =============================================================================
println("\n41. The clock is read once the tick has the lock")

# A save's poke passes no time, so this part uses the real clock — with a send
# time three hours from now, so that the answer does not depend on the hour.
hh41 = Dates.format(now() + Hour(3), "HH:MM")
write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = \"$(hh41)\""))
fresh_schedule!(Notify.latest_cutoff(now(), Notify.settings().send_at))
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: behind the lock)")
const T41 = Ref(DateTime(0))
lock(Notify.BUSY)
try
    Notify.SCHEDULE[] = Timer(3600)           # a stand-in, so that poke acts
    Notify.poke()
    sleep(2.0)
    ok("a poke made while a tick holds the lock waits for it", SEND_TRIES[] == 0)
    T41[] = now()
finally
    unlock(Notify.BUSY)
end
for _ in 1:200
    (SEND_TRIES[] >= 1 && !islocked(Notify.BUSY)) && break
    sleep(0.05)
end
ok("and runs once the lock is free", SEND_TRIES[] == 1)
ok("reading the clock then, not when the save asked for it",
   Notify.BACKOFF[] !== nothing && Notify.BACKOFF[].until - Minute(5) >= T41[])
pw41 = string(get(pending_of(state()), "written", ""))
ok("the hand-over it wrote down is dated then too",
   !isempty(pw41) && DateTime(pw41, dateformat"yyyy-mm-dd HH:MM:SS") >= floor(T41[], Second))
Notify.SCHEDULE[] === nothing || close(Notify.SCHEDULE[])
Notify.SCHEDULE[] = nothing
SEND_FAIL[] = nothing
write(CONFIG, SETTINGS)

println("\n   Time spent earlier in the tick counts against the last minute")
fresh_schedule!(DateTime(2032, 5, 1, 17, 30))
logged!(DateTime(2032, 5, 2, 10, 0), Date(2032, 5, 2))
Notify.MAILER[] = (send = (k, e, i) -> (sleep(3.0); fake_send(k, e, i)), cancel = fake_cancel)
res = tick_at(DateTime(2032, 5, 3, 17, 28, 58))
ok("a late report that took three seconds leaves under a minute, so the coming one is not handed over",
   res == [:late] && length(CREATES) == 1 && startswith(created().idem, "ldgr-late-"))
Notify.MAILER[] = FAKE

# =============================================================================
# 42. A send time written with seconds (F14)
# =============================================================================
println("\n42. A send time written with seconds")

write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = 17:30:00.5"))
ok("send_at = 17:30:00.5, an unquoted TOML time with a fraction of a second, is read as 5:30 pm",
   Notify.settings() !== nothing && Notify.settings().send_at == Time(17, 30))
fresh_schedule!(DateTime(2032, 7, 1, 17, 30))
r42 = [tick_at(DateTime(2032, 7, 2, 9, 0)), tick_at(DateTime(2032, 7, 2, 9, 1)), tick_at(DateTime(2032, 7, 2, 9, 2))]
ok("one version is handed over, and the next ticks find it current",
   r42 == [[:scheduled], [:idle], [:idle]] && length(CREATES) == 1)
ok("for 5:30 pm exactly",
   sched_of(created()) == Notify._utc_text(DateTime(2032, 7, 2, 17, 30)) &&
   get(state(), "cutoff", "") == "2032-07-02 17:30:00")
write(CONFIG, replace(SETTINGS, "send_at = \"17:30\"" => "send_at = 17:30:45"))
ok("whole seconds are dropped too", Notify.settings() !== nothing && Notify.settings().send_at == Time(17, 30))
write(CONFIG, SETTINGS)

# =============================================================================
# 43. Resend.jl again (F15, F16, F17)
# =============================================================================
println("\n43. Resend.jl again: the key in a long refusal, a certificate, a cut-off reply, cancels")

Resend.API_BASE[] = STUB2_BASE
local_only()
Resend.TIMEOUTS[] = (connect = 2, read = 3)
STUB_MODE[] = :auto

const LONG422 = "{\"statusCode\":422,\"name\":\"validation_error\",\"message\":\"" * "x"^170 * " key " * KEY * "\"}"
e = refusal(422, LONG422)
ok("a 422 whose message ends with the key past the 200th character: a settings Failure", isfailure(e, :settings))
ok("with not eight characters of the key in a row left in its words",
   e isa Resend.Failure && !leaks_key(e.words) && occursin("********", e.words))
ok("the same straight from Resend._failure", !leaks_key(Resend._failure(422, LONG422, KEY).words))
ok("an old key that notify.toml no longer holds is masked by Notify._scrub",
   Notify._scrub("Resend said: bad key re_OLDkey_1234567890abc") == "Resend said: bad key ********")
ok("and by Resend._scrub", Resend._scrub("old key re_OLDkey_1234567890abc here", KEY) == "old key ******** here")
ok("an email id and an ordinary word are left alone",
   Notify._scrub("id 4f1c2d3e-0000-4000-8000-123456789abc; care_about_it_always") ==
   "id 4f1c2d3e-0000-4000-8000-123456789abc; care_about_it_always")

println("\n   A certificate that cannot be checked")
req43 = HTTP.Request("POST", "/emails")
w43 = Resend._network_words(HTTP.Exceptions.ConnectError("https://127.0.0.1:1/emails",
          CapturedException(Fakes.OpenSSLError("certificate has expired"), backtrace())))
ok("an OpenSSL certificate error is not called 'no internet': it names the certificate and the clock",
   occursin("could not be checked (certificate has expired)", w43) && occursin("date and time", w43) &&
   !occursin("could not be reached", w43))
w43 = Resend._network_words(HTTP.Exceptions.RequestError(req43,
          CompositeException(Any[task_error(Fakes.MbedException(-9984))])))
ok("nor is an MbedTLS one, found inside a failed task", occursin("date and time", w43))
w43 = Resend._network_words(HTTP.Exceptions.RequestError(req43,
          CompositeException(Any[task_error(EOFError())])))
ok("a reply cut off inside a failed task is called cut off", occursin("the connection was cut off", w43))
w43 = Resend._network_words(HTTP.Exceptions.RequestError(req43, Fakes.TimeoutException(3.0)))
ok("a ConcurrentUtilities timeout counts as no answer in time",
   occursin("no answer came within $(Resend.TIMEOUTS[].read) seconds", w43))

opensslexe = Sys.which("openssl")
if opensslexe === nothing
    println("      (openssl is not on PATH: the self-signed HTTPS stub is skipped)")
else
    tlsdir = mktempdir()
    certp = joinpath(tlsdir, "cert.pem"); keyp = joinpath(tlsdir, "key.pem")
    made43 = try
        cmd43 = `$(opensslexe) req -x509 -newkey rsa:2048 -nodes -keyout $(keyp) -out $(certp) -days 2 -subj /CN=127.0.0.1`
        run(pipeline(cmd43; stdout = devnull, stderr = devnull))
        isfile(certp) && isfile(keyp)
    catch
        false
    end
    if !made43
        println("      (openssl could not make a certificate: the self-signed HTTPS stub is skipped)")
    else
        tlsport = spare_port()
        tls43 = Logging.with_logger(Logging.NullLogger()) do
            HTTP.serve!(req -> HTTP.Response(200, ["Content-Type" => "application/json"], "{\"id\":\"tls\"}"),
                        "127.0.0.1", tlsport; sslconfig = HTTP.MbedTLS.SSLConfig(certp, keyp))
        end
        Resend.API_BASE[] = "https://127.0.0.1:$(tlsport)"
        e = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM))
        ok("a real HTTPS stub with a self-signed certificate: temporary, and the words point at the clock",
           isfailure(e, :temporary) && occursin("date and time", e.words) &&
           !occursin("could not be reached", e.words) && !leaks_key(e.words))
        try
            HTTP.forceclose(tls43)
        catch
        end
        Resend.API_BASE[] = STUB2_BASE
    end
end

println("\n   A reply cut off half way")
cport43, csrv43 = Sockets.listenany(Sockets.ip"127.0.0.1", rand(49152:64000))
@async while isopen(csrv43)
    s = try
        Sockets.accept(csrv43)
    catch
        break
    end
    @async try
        readavailable(s)
        write(s, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{\"id\":\"ab")
        close(s)
    catch
    end
end
Resend.API_BASE[] = "http://127.0.0.1:$(Int(cport43))"
e = via_stub(() -> Resend.send(KEY, EM; idempotency_key = IDEM))
close(csrv43)
Resend.API_BASE[] = STUB2_BASE
ok("a reply that stops half way through its body is temporary, and called cut off",
   isfailure(e, :temporary) && occursin("the connection was cut off", e.words))

println("\n   Cancel answers that do not mean the email is gone")
e = refusal(301, ""; cancel = true)
ok("a cancel answered with a redirect (301) throws: it was not confirmed", isfailure(e, :temporary))
e = refusal(408, "{\"statusCode\":408,\"name\":\"request_timeout\",\"message\":\"Request timed out\"}"; cancel = true)
ok("so does a 408", isfailure(e, :temporary))
e = refusal(429, "{\"statusCode\":429,\"name\":\"rate_limit_exceeded\",\"message\":\"Too many requests\"}"; cancel = true)
ok("and a 429", isfailure(e, :temporary))
e = refusal(500, "{\"statusCode\":500,\"name\":\"application_error\",\"message\":\"Internal server error\"}"; cancel = true)
ok("and a 500", isfailure(e, :temporary))
e = refusal(403, "{\"statusCode\":403,\"name\":\"invalid_api_key\",\"message\":\"API key is invalid\"}"; cancel = true)
ok("a 403 about the key is a settings Failure", isfailure(e, :settings))
e = refusal(404, "{\"statusCode\":404,\"name\":\"not_found\",\"message\":\"Email not found\"}"; cancel = true)
ok("a 404 means there is nothing left to cancel", e === nothing)
e = refusal(422, "{\"statusCode\":422,\"name\":\"validation_error\",\"message\":\"Email already sent\"}"; cancel = true)
ok("and so does a 422", e === nothing)
STUB_MODE[] = :auto
try
    HTTP.forceclose(STUB2)
catch
end

# =============================================================================
# 44. A ledger released by an edit, and what a day did not balance by
# =============================================================================
println("\n44. A ledger released by an edit; the difference before a run of edits")

const SNAP44 = logsnap()

# A same-date correction of 21 March that let 22 March's held ledger be made.
logrow!(DateTime(2033, 3, 21, 18, 0), Date(2033, 3, 21); what = "edited",
        changed = "Cash Sales \$100.00 -> \$0.00; Closing Balance \$1,100.00 -> \$1,000.00")
Changes._append!(Changes.Row[Changes.Row((DateTime(2033, 3, 21, 18, 0), "tester", "released",
                                          Date(2033, 3, 22), "trading", "", "written",
                                          -25.0, 0.0, "short at lunch", "", NaN, NaN, "",
                                          false, false, false, false, Date(2033, 3, 21)))])
s44, b44 = Notify.build_digest(DateTime(2033, 3, 21, 17, 30), DateTime(2033, 3, 22, 17, 30))
sec44 = section(b44, "CHANGES TO DAYS ALREADY SAVED")
ok("a ledger released by a same-date correction is reported", occursin("The ledger for 22 March 2033 was made.", sec44))
ok("with the difference that came to light, and its reason",
   occursin("Shortage of \$25.00 during that day.", sec44) && occursin("short at lunch", sec44))
ok("saying the correction let it be made",
   occursin("It was corrected on the date it was first typed in, which let a waiting ledger be made.", sec44))
ok("the correction's own figures stay unlisted, as the same-date rule says",
   !occursin("Cash Sales \$100.00 -> \$0.00", b44))
ok("and the report does not claim nothing happened",
   !occursin("The only changes were corrections", b44) && !occursin("Nothing was entered", b44))
ok("the subject counts the day and the difference the body shows",
   occursin("1 day changed", s44) && occursin("1 difference", s44))
write(LOGP, SNAP44)

# Two later-date edits that together made 24 March balance.
logrow!(DateTime(2033, 3, 25, 9, 0), Date(2033, 3, 24); what = "edited", day_diff = -40.0,
        was_day = -100.0, changed = "Closing Balance \$900.00 -> \$960.00", cross = true)
logrow!(DateTime(2033, 3, 25, 9, 5), Date(2033, 3, 24); what = "edited", day_diff = 0.0,
        was_day = -40.0, changed = "Closing Balance \$960.00 -> \$1,000.00", cross = true, balances = true)
s44, b44 = Notify.build_digest(DateTime(2033, 3, 24, 17, 30), DateTime(2033, 3, 25, 17, 30))
sec44 = section(b44, "CHANGES TO DAYS ALREADY SAVED")
ok("two later-date edits that made a day balance are both shown",
   occursin("\$900.00 -> \$960.00", sec44) && occursin("\$960.00 -> \$1,000.00", sec44))
ok("and 'did not balance before' is the difference before the first edit shown",
   occursin("It did not balance before: shortage of \$100.00 during the day.", sec44) &&
   !occursin("shortage of \$40.00", sec44))
ok("then 'It balances now.'", occursin("It balances now.", sec44))
write(LOGP, SNAP44)

# =============================================================================
# 45. Damaged lines the writer mends and the reader names
# =============================================================================
println("\n45. A line cut inside quotation marks, a date cut short, an emptied log")

const SNAP45 = logsnap()
n45 = length(Changes._read_log())
d45 = count(==('\n'), SNAP45) - 1                  # data lines in the log as it was
good45 = rawrow("2033-04-01 09:00:00", "2033-04-01")
torn45 = "2033-04-01 10:00:00,tester,edited,2033-03-31,trading,replaced,written,0.0,0.0,,,,," *
         "\"Closing Balance \$1,000.00 -> "
write(LOGP, SNAP45 * good45 * "\n" * torn45)           # cut inside a quoted cell, no newline
logged!(DateTime(2033, 4, 1, 11, 0), Date(2033, 4, 1))  # the next save, through Changes._write
rows45, prob45 = Changes.rows_checked(DateTime(2033, 3, 31, 17, 30), DateTime(2033, 4, 1, 17, 30))
ok("a save after a line cut inside quotation marks still reads",
   any(r -> r.when == DateTime(2033, 4, 1, 11, 0), rows45))
ok("so does the good line before the cut", any(r -> r.when == DateTime(2033, 4, 1, 9, 0), rows45))
ok("the cut line is named on its own", prob45 == line_problem(d45 + 2))
ok("and the rest of the log still reads", length(Changes._read_log()) == n45 + 2)

write(LOGP, SNAP45 * "2033-04-2\n")                     # a line cut inside its date
_, prob45 = Changes.rows_checked(DateTime(2033, 4, 2, 17, 30), DateTime(2033, 4, 3, 17, 30))
ok("a line cut inside its date is not dated some other day: the report it may belong to names it",
   !isempty(prob45))

relrow(last) = join(["2033-04-05 10:00:00", "tester", "released", "2033-04-06", "trading", "", "written",
                     "-25.0", "0.0", "short", "", "", "", "", "false", "false", "false", "false", last], ",")
write(LOGP, SNAP45 * relrow("2033-04-") * "\n")
rows45, prob45 = Changes.rows_checked(DateTime(2033, 4, 4, 17, 30), DateTime(2033, 4, 5, 17, 30))
ok("a released row cut inside its last cell is named, not read as releasing another day",
   isempty(rows45) && !isempty(prob45))
write(LOGP, SNAP45 * relrow("") * "\n")
rows45, prob45 = Changes.rows_checked(DateTime(2033, 4, 4, 17, 30), DateTime(2033, 4, 5, 17, 30))
ok("and so is one cut just before it", isempty(rows45) && !isempty(prob45))
write(LOGP, SNAP45 * relrow("2033-04-05") * "\n")
rows45, prob45 = Changes.rows_checked(DateTime(2033, 4, 4, 17, 30), DateTime(2033, 4, 5, 17, 30))
ok("a whole released row still reads",
   length(rows45) == 1 && prob45 == "" && rows45[1].released_by == Date(2033, 4, 5))

write(LOGP, SNAP45 * "2033-04-09 10:00:00,tester,saved,2033-04-09,trading,added,written,0.0,0.0," *
            "\"short, recounted,,,,,false,false,false,false,\n" * rawrow("2033-04-09 11:00:00", "2033-04-09") * "\n")
_, prob45 = Changes.rows_checked(DateTime(2033, 4, 8, 17, 30), DateTime(2033, 4, 9, 17, 30))
ok("a log that cannot be read at all says a line is damaged, in plain words",
   prob45 == "A line of the change log is damaged (for example a quotation mark that is never closed), " *
             "so none of it could be read.")
mended45 = try
    write(LOGP, SNAP45); true
catch
    false
end
ok("and the file can be mended while ldgr runs: the failed read left it unlocked", mended45)

write(LOGP, "﻿\r\n")                               # emptied in a spreadsheet
logged!(DateTime(2033, 4, 12, 10, 0), Date(2033, 4, 12))
rows45, prob45 = Changes.rows_checked(DateTime(2033, 4, 11, 17, 30), DateTime(2033, 4, 12, 17, 30))
ok("a log emptied to a byte-order mark is written afresh, with its heading",
   length(rows45) == 1 && prob45 == "" && startswith(read(LOGP, String), "when,"))
write(LOGP, SNAP45)

# =============================================================================
# 46. A hand-over that never left, a replay during a cancel pause, a stray byte
# =============================================================================
println("\n46. A hand-over that never left; a replay confirmed during a cancel pause; a stray byte")

write(CONFIG, SETTINGS)
fresh_schedule!(DateTime(2033, 5, 1, 17, 30))
logged!(DateTime(2033, 5, 2, 10, 0), Date(2033, 5, 2))
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: offline)", false)
res = tick_at(DateTime(2033, 5, 2, 10, 0, 30))
ok("a hand-over that never left this computer fails", res == [:failed])
ok("and leaves nothing pending: Resend cannot have made it", !haskey(state(), "pending"))
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "was cut off. (test: it may have arrived)")
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 5, 2, 10, 10))
ok("one that may have reached Resend stays pending, to be asked about again",
   res == [:failed] && haskey(state(), "pending"))
SEND_FAIL[] = nothing

fresh_schedule!(DateTime(2033, 5, 3, 17, 30))
tick_at(DateTime(2033, 5, 4, 9, 0))
v46a = created().id
logged!(DateTime(2033, 5, 4, 10, 0), Date(2033, 5, 4))
CANCEL_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: no answer came " *
                                           "within 30 seconds. (test: cancel)")
tick_at(DateTime(2033, 5, 4, 10, 0, 30))
v46b = created().id
CANCEL_FAIL[] = nothing
ok("a cancel failed, so a cancel pause is running",
   Notify.CANCEL_BACKOFF[] !== nothing && leftovers() == [v46a])
logged!(DateTime(2033, 5, 4, 10, 1), Date(2033, 5, 4))
LOSE_REPLY[] = true
res = tick_at(DateTime(2033, 5, 4, 10, 1, 30); poked = true)
v46c = created().id
ok("the next hand-over's answer is lost", res == [:failed] && haskey(state(), "pending"))
res = tick_at(DateTime(2033, 5, 4, 10, 2); poked = true)
ok("when the replay is confirmed, the versions it replaces are cancelled at once, pause or not",
   res == [:scheduled, :cancelled, :cancelled] && isempty(leftovers()))
ok("so exactly one version is left waiting", live_ids() == [v46c] && get(state(), "id", "") == v46c)

fresh_schedule!(DateTime(2033, 5, 5, 17, 30))
Changes._append!(Changes.Row[Changes.Row((DateTime(2033, 5, 6, 10, 0), "Jos\xe9", "saved",
                                          Date(2033, 5, 6), "trading", "added", "written",
                                          -10.0, 0.0, "caf\xe9 run", "", NaN, NaN, "",
                                          false, false, false, false, nothing))])
res = tick_at(DateTime(2033, 5, 6, 10, 1))
ok("a stray byte in the change log does not stop the report being handed over", res == [:scheduled])
ok("it is shown as a replacement character", occursin("Jos�", body_of(created())) &&
                                               occursin("caf� run", body_of(created())))
ok("and the state file still reads back", get(state(), "id", "") == created().id)
write(LOGP, SNAP45)

println("\n   The two UTF-8 cleaners, each on its own")
Changes._append!(Changes.Row[Changes.Row((DateTime(2033, 5, 6, 10, 0), "Jos\xe9", "saved",
                                          Date(2033, 5, 6), "trading", "added", "written",
                                          -10.0, 0.0, "caf\xe9 run", "", NaN, NaN, "",
                                          false, false, false, false, nothing))])
r46x = filter(r -> r.when == DateTime(2033, 5, 6, 10, 0), Changes._read_log())
ok("the change log reader itself turns a stray byte into the replacement character",
   length(r46x) == 1 && r46x[1].who == "Jos\ufffd" && r46x[1].reason == "caf\ufffd run")
e46x = Notify._email_dict("ldgr@example.invalid", "owner@example.invalid", "report \xff", "caf\xe9", "")
ok("and an email is handed over as valid UTF-8 whatever text it was built from",
   isvalid(e46x["subject"]) && e46x["subject"] == "report \ufffd" && e46x["text"] == "caf\ufffd")
write(LOGP, SNAP45)

println("\n   Never sent, told apart from maybe sent")
ce46x = HTTP.Exceptions.ConnectError("http://127.0.0.1:1/emails",
                                     Base.IOError("connect: connection refused (ECONNREFUSED)", -4078))
ok("a connection that could not be opened counts as never sent, bare or inside a RequestError",
   Resend._before_sending(ce46x) &&
   Resend._before_sending(HTTP.Exceptions.RequestError(HTTP.Request("POST", "/emails"), ce46x)) &&
   !Resend._before_sending(HTTP.Exceptions.TimeoutError(2)))

fresh_schedule!(DateTime(2033, 5, 10, 17, 30))
logged!(DateTime(2033, 5, 11, 10, 0), Date(2033, 5, 11))
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: offline, late)", false)
res46z = tick_at(DateTime(2033, 5, 12, 9, 0))
SEND_FAIL[] = nothing
ok("a late report that never left this computer fails and leaves nothing pending",
   res46z == [:failed] && isfile(statefile()) && !haskey(state(), "pending"))

println("\n   A version given up on in the last minute, reported late later")
fresh_schedule!(DateTime(2033, 5, 13, 17, 30))
logged!(DateTime(2033, 5, 14, 10, 0), Date(2033, 5, 14))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 5, 14, 17, 28, 10); poked = true)       # made at Resend, the answer lost
res = tick_at(DateTime(2033, 5, 14, 17, 29, 15); poked = true)
ok("a hand-over unconfirmed a minute before the send time is given up on, not asked about again",
   res == [:idle] && !haskey(state(), "pending") && get(state(), "unsure", "") == "2033-05-14 17:30:00")
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 5, 14, 17, 34))
late46 = [c for c in CREATES if startswith(c.idem, "ldgr-late-")]
ok("the late report that follows, on a later tick, still says it may repeat the 5:30 pm one",
   res == [:late, :scheduled] && length(late46) == 1 &&
   occursin("This report may repeat one sent at 5:30 pm", flat(body_of(late46[1]))))
ok("and the uncertain send time is forgotten once it is covered", !haskey(state(), "unsure"))

fresh_schedule!(DateTime(2033, 5, 15, 17, 30))
logged!(DateTime(2033, 5, 16, 10, 0), Date(2033, 5, 16))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 5, 16, 17, 20, 10); poked = true)
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: offline again)", false)
res = tick_at(DateTime(2033, 5, 16, 17, 31))
SEND_FAIL[] = nothing
ok("given up on after the send time, with the late report's first try never leaving the computer",
   res == [:failed] && get(state(), "unsure", "") == "2033-05-16 17:30:00")
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 5, 16, 17, 37))
late46 = [c for c in CREATES if startswith(c.idem, "ldgr-late-")]
ok("the retry still says it may repeat the 5:30 pm one",
   res == [:late, :scheduled] && !isempty(late46) &&
   occursin("This report may repeat one sent at 5:30 pm", flat(body_of(late46[end]))))

println("\n   A tick that fails unexpectedly")
write(CONFIG, SETTINGS)
fresh_schedule!(DateTime(2033, 5, 17, 17, 30))
Notify.LAST_UNEXPECTED[] = ("", DateTime(0))
tick_at(DateTime(2033, 5, 18, 8, 0))                           # a state file exists first
n46y = count_of("email: the daily report could not be prepared:", auditlog())
mkpath(statefile() * ".tmp")                                   # its temporary copy cannot be written
logged!(DateTime(2033, 5, 18, 8, 30), Date(2033, 5, 18))       # so the next hand-over must write it
res46y = [tick_at(DateTime(2033, 5, 18, 9, m)) for m in 0:2]
ok("an unexpected failure inside a tick is thrown, and written to the audit log first",
   all(==([:threw]), res46y) && count_of("email: the daily report could not be prepared:", auditlog()) == n46y + 1)
tick_at(DateTime(2033, 5, 18, 10, 5))
ok("the same failure an hour later is written again, once",
   count_of("email: the daily report could not be prepared:", auditlog()) == n46y + 2)
rm(statefile() * ".tmp"; recursive = true, force = true)

println("\n   A quote typed by hand into the middle of a cell")
write(LOGP, SNAP45 * rawrow("2033-05-20 09:00:00", "2033-05-20"; changed = "5\" drawer") * "\n")
logged!(DateTime(2033, 5, 20, 10, 0), Date(2033, 5, 20))
logged!(DateTime(2033, 5, 20, 11, 0), Date(2033, 5, 20))
rows46q, prob46q = Changes.rows_checked(DateTime(2033, 5, 19, 17, 30), DateTime(2033, 5, 20, 17, 30))
ok("is read as an ordinary character, and the saves after it still read",
   length(rows46q) == 3 && prob46q == "" && rows46q[1].changed == "5\" drawer")
write(LOGP, SNAP45)

# =============================================================================
# 47. A line cut after spaces before a quote, and a heading cut short (B1, B2)
# =============================================================================
println("\n47. A cut inside a quoted cell that begins with a space or a tab, and a heading cut short")

# The writer decides whether the last line was cut inside a quoted cell
# (`_ends_in_quote`), and closes the quote if it was. CSV.jl, reading with the
# options `_parse` uses, takes a quote after leading spaces or tabs as opening a
# quoted cell, so the writer has to as well. And a first-ever write cut inside
# the heading line holds no data, so it is written afresh (`_blank`).

const SNAP47 = logsnap()
ok("(the change log reads cleanly to begin with)",
   Changes.rows_checked(nothing, DateTime(2100, 1, 1))[2] == "")
const d47 = nlogrows()

println("\n   _ends_in_quote, on bytes")
inq(s) = Changes._ends_in_quote(Vector{UInt8}(codeunits(s)))
ok("a cut inside a quoted cell that holds a line break is open",
   inq("2033,x,\"first line\nsecond line, cut"))
ok("so is a cut just after an escaped pair", inq("2033,x,\"said \"\"ok\"\" and then"))
ok("and one that ends on the escaped pair itself", inq("2033,x,\"said \"\"ok\"\""))
ok("a closed cell holding an escaped pair and a line break is not open",
   !inq("2033,x,\"said \"\"ok\"\"\nand more\",y\n"))
ok("nor is a closed cell with a line break, cut after its comma",
   !inq("2033,x,\"first line\nsecond line\","))
ok("a quote closed at the very end is not open", !inq("2033,x,\"closed\""))
ok("a space before the opening quote: open when cut", inq("2033,x, \"a reason, cut"))
ok("a space before the opening quote: closed when closed", !inq("2033,x, \"a reason, done\",y\n"))
ok("a tab before the opening quote: open when cut", inq("2033,x,\t\"a reason, cut"))
ok("a tab before the opening quote: closed when closed", !inq("2033,x,\t\"a reason, done\",y\n"))
ok("several spaces and a tab before it: open when cut", inq("2033,x,  \t  \"a reason, cut"))
ok("several spaces before it: closed when closed", !inq("2033,x,   \"a reason\",y\n"))
ok("a space before the first quote of a line: open when cut", inq("2033,x,y\n \"a reason, cut"))
ok("a cut with only spaces or a tab so far is not open", !inq("2033,x, ") && !inq("2033,x,\t") && !inq("2033,x, \t "))
ok("spaces after a closing quote, before the comma, leave it closed", !inq("2033,\"abc\" ,x"))
ok("a space and a quote in the middle of an ordinary cell is not a cut", !inq("2033,ab \"x,y") && !inq("2033,ab\t\"x,y"))
ok("a quote in the middle of a cell typed by hand is not a cut", !inq("2033,5\" drawer,x"))
ok("nor is an empty file, or a line break", !inq("") && !inq("\n") && !inq("\r\n"))

println("\n   A line cut as `..., \"a reason, cut`, then a real save")
for (label, lead) in (("a space", " "), ("a tab", "\t"), ("three spaces", "   "))
    local torn = "2033-06-01 10:00:00,tester,saved,2033-06-01,trading,added,written,-25.0,0.0," *
                 lead * "\"a reason, cut"
    write(LOGP, SNAP47 * rawrow("2033-06-01 09:00:00", "2033-06-01") * "\n" * torn)
    logged!(DateTime(2033, 6, 1, 11, 0), Date(2033, 6, 1))
    local rows, prob = Changes.rows_checked(DateTime(2033, 5, 31, 17, 30), DateTime(2033, 6, 1, 17, 30))
    ok("$label before the quote: the save after the cut reads, and so does the row before it",
       length(rows) == 2 && rows[end].when == DateTime(2033, 6, 1, 11, 0) &&
       rows[1].when == DateTime(2033, 6, 1, 9, 0))
    ok("$label before the quote: only the cut line is named, not the whole log",
       prob == line_problem(d47 + 2) && length(Changes._read_log()) == d47 + 2)
    ok("$label before the quote: the cut line's quote is closed and it stays on its own line",
       loglines()[end-1] == torn * "\"" && startswith(loglines()[end], "2033-06-01 11:00:00,"))
end

println("\n   A heading cut short, then a real save")
rm(LOGP)
logged!(DateTime(2033, 6, 2, 9, 0), Date(2033, 6, 2))
ok("the heading the writer uses is what a fresh log begins with",
   startswith(logsnap(), Changes._header_line()) && Changes._header_line() == join(Changes.COLUMNS, ",") * "\n")
for (label, text) in (("cut inside a name", "when,who,wha"),
                      ("cut after a comma", "when,who,"),
                      ("one letter", "w"),
                      ("cut inside a name with a space in it", "when,who,what,day,day ki"),
                      ("cut after a name with a space in it, and a space", "when,who,what,day,day kind "),
                      ("a byte-order mark and the start", "﻿when,who"),
                      ("the start and a line break", "when,who,what\n"),
                      ("the whole heading with no line break", join(Changes.COLUMNS, ",")))
    write(LOGP, text)
    ok("$label: counts as holding no data", Changes._blank(LOGP))
    logged!(DateTime(2033, 6, 3, 9, 0), Date(2033, 6, 3))
    logged!(DateTime(2033, 6, 3, 10, 0), Date(2033, 6, 4))
    local rows, prob = Changes.rows_checked(nothing, DateTime(2100, 1, 1))
    ok("$label: the log reads, with both saves and no complaint",
       prob == "" && length(rows) == 2 && rows[1].when == DateTime(2033, 6, 3, 9, 0) &&
       rows[2].day == Date(2033, 6, 4))
    ok("$label: the heading is whole, and there is only one",
       loglines()[1] == join(Changes.COLUMNS, ",") && length(loglines()) == 3 &&
       count(l -> startswith(l, "when,"), loglines()) == 1)
end

println("\n   Any other damaged heading is left alone")
for (label, text) in (("a name that is wrong", "when,who,wat"),
                      ("a name that is misspelt past the end", "when,who,what,"  * "dayy"),
                      ("a line of data under a cut heading", "when,who,wha\n2033-06-05 09:00:00,tester"),
                      ("a lone data line", "2033-06-05 09:00:00,tester,saved"),
                      ("a comma with nothing else", ",when"))
    write(LOGP, text)
    ok("$label: does not count as holding no data", !Changes._blank(LOGP))
    logged!(DateTime(2033, 6, 5, 10, 0), Date(2033, 6, 5))
    ok("$label: what was there is kept, and the save is added after it",
       startswith(logsnap(), text) && startswith(loglines()[end], "2033-06-05 10:00:00,tester,saved,"))
end

write(LOGP, SNAP47)
ok("(the change log is put back)", logsnap() == SNAP47 && Changes.rows_checked(nothing, DateTime(2100, 1, 1))[2] == "")

# =============================================================================
# 48. A version given up on says so in every report that covers it; an unexpected
#     error is said on the terminal once an hour; an audit line that could not be
#     written is not counted as written
# =============================================================================
println("\n48. The 'may repeat' note in every report; one terminal warning an hour; an unwritable audit log")

write(CONFIG, SETTINGS)
const R4A_LOG = logsnap()
r4a_made(prefix) = [c for c in CREATES if startswith(c.idem, prefix)]
const R4A_AGAIN = "This report may repeat one sent at 5:30 pm: ldgr could not confirm that Resend had " *
                  "received it before ldgr was closed or went offline. If both arrived, this one is complete."
const R4A_TWO = "Two reports may arrive at 5:30 pm: ldgr handed an earlier version of this one to " *
                "Resend but could not confirm that Resend had received it, so it could not cancel it. " *
                "If both arrive, this one is complete."

println("\n   The sentence itself: one rule, worked out from the stretch a report covers")
u = DateTime(2033, 6, 2, 17, 30)
ok("no version given up on: no sentence, for any kind of report",
   Notify._repeat_note(nothing, nothing, u) == "" &&
   Notify._repeat_note(nothing, nothing, u; scheduled = true) == "")
ok("a send time inside the stretch: the late wording, exactly",
   Notify._repeat_note(u, DateTime(2033, 6, 1, 17, 30), u) == R4A_AGAIN)
ok("the first report ever (no start) covers it too", Notify._repeat_note(u, nothing, u) == R4A_AGAIN)
ok("a stretch that starts AT the send time does not: it was covered by the report before",
   Notify._repeat_note(u, u, u + Day(1)) == "")
ok("nor one that ends before it", Notify._repeat_note(u, DateTime(2033, 6, 1, 17, 30), u - Minute(1)) == "")
ok("a scheduled version for that very send time says two reports may arrive",
   Notify._repeat_note(u, DateTime(2033, 6, 1, 17, 30), u; scheduled = true) == R4A_TWO)
ok("one for a later send time says it may repeat the earlier one, and does not claim they arrive together",
   Notify._repeat_note(u, DateTime(2033, 6, 1, 17, 30), u + Day(1); scheduled = true) ==
   "This report may repeat one sent at 5:30 pm on 2 June 2033: ldgr handed an earlier version to Resend " *
   "but could not confirm that Resend had received it. If both arrive, this one is complete.")
ok("a send time on another day than the report's is named, for a report sent at once too",
   occursin("sent at 5:30 pm on 2 June 2033:", Notify._repeat_note(u, nothing, u + Day(2))))
ok("and it is the same words every time (the text feeds the idempotency key)",
   Notify._repeat_note(u, nothing, u; scheduled = true) == Notify._repeat_note(u, nothing, u; scheduled = true))

println("\n   (a) A corrected report, after the version that replaced the first was lost")
fresh_schedule!(DateTime(2033, 6, 1, 17, 30))
tick_at(DateTime(2033, 6, 2, 9, 0))
r4a_v1 = created()
logged!(DateTime(2033, 6, 2, 10, 0), Date(2033, 6, 2))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 6, 2, 17, 20); poked = true)            # v2 made at Resend, the answer lost
res = tick_at(DateTime(2033, 6, 2, 17, 29, 15); poked = true)
ok("the lost version is given up on a minute before its send time, and remembered",
   res == [:idle] && get(state(), "unsure", "") == "2033-06-02 17:30:00" && !haskey(state(), "pending"))
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 6, 2, 17, 34))
fix_a = r4a_made("ldgr-fix-")
ok("a corrected report goes out", :sent in res && length(fix_a) == 1)
ok("it says it replaces the 5:30 pm one, and that it may repeat one that could not be confirmed",
   length(fix_a) == 1 &&
   occursin("This replaces the report sent at 5:30 pm, which was prepared before the last entry of " *
            "that day could be sent. " * R4A_AGAIN, flat(body_of(fix_a[1]))))
ok("the uncertain send time is forgotten once the corrected report is out", !haskey(state(), "unsure"))
ok("and the next scheduled version does not carry the sentence",
   !occursin("may repeat", body_of(created())) && !occursin("may arrive", body_of(created())))

println("\n   (a) A follow-up report, after a fresh problem reading the change log")
fresh_schedule!(DateTime(2033, 6, 3, 17, 30))
sn_a2 = logsnap()
tick_at(DateTime(2033, 6, 4, 9, 0))
append_raw!("2033-06-04 10:00:00,tester,sav\n")                # too few cells: a line that cannot be read
LOSE_REPLY[] = true
tick_at(DateTime(2033, 6, 4, 17, 20); poked = true)
res = tick_at(DateTime(2033, 6, 4, 17, 29, 15); poked = true)
ok("given up on again, the send time remembered",
   res == [:idle] && get(state(), "unsure", "") == "2033-06-04 17:30:00")
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 6, 4, 17, 34))
fix_a2 = r4a_made("ldgr-fix-")
ok("a follow-up report goes out", :sent in res && length(fix_a2) == 1)
ok("it says it follows the 5:30 pm one, and that it may repeat one that could not be confirmed",
   length(fix_a2) == 1 &&
   occursin("This follows the report sent at 5:30 pm.", flat(body_of(fix_a2[1]))) &&
   occursin(R4A_AGAIN, flat(body_of(fix_a2[1]))))
ok("and is not marked as a corrected report", length(fix_a2) == 1 && !occursin("corrected", subject_of(fix_a2[1])))
ok("the uncertain send time is forgotten", !haskey(state(), "unsure"))
write(LOGP, sn_a2)

println("\n   (b) The first report ever, after a version was given up on")
fresh_schedule!(nothing)
write(LOGP, first(split(R4A_LOG, '\n')) * "\n")                # a log holding only what this scenario writes
logged!(DateTime(2033, 6, 6, 10, 0), Date(2033, 6, 6))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 6, 6, 17, 20); poked = true)
res = tick_at(DateTime(2033, 6, 6, 17, 29, 15); poked = true)
ok("the lost version is given up on, with no marker yet",
   res == [:idle] && get(state(), "unsure", "") == "2033-06-06 17:30:00" && Notify.last_reported() === nothing)
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 6, 6, 17, 34))
late_b = r4a_made("ldgr-late-")
ok("the first report goes out at once", :late in res && length(late_b) == 1)
ok("it keeps its own sentence and adds the one about the repeat",
   length(late_b) == 1 &&
   occursin("This is the first report since email was set up, so it covers everything in the change log " *
            "up to 5:30 pm on 6 June 2033. " * R4A_AGAIN, flat(body_of(late_b[1]))))
ok("the uncertain send time is forgotten", !haskey(state(), "unsure"))
write(LOGP, R4A_LOG)

println("\n   (c) A hand-over given up on after 23 hours, with its send time still ahead")
fresh_schedule!(DateTime(2033, 6, 7, 17, 30))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 6, 8, 17, 35))                          # for 9 June, made at Resend, the answer lost
r4a_lost = created()
ok("the first hand-over is for 9 June at 5:30 pm and carries no sentence",
   r4a_lost.email["scheduled_at"] == Notify._utc_text(DateTime(2033, 6, 9, 17, 30)) &&
   !occursin("may repeat", body_of(r4a_lost)) && !occursin("may arrive", body_of(r4a_lost)))
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 6, 9, 17, 0))
ok("more than 23 hours on it is given up on, and a new version is handed over for the same send time",
   res == [:scheduled] && get(state(), "unsure", "") == "2033-06-09 17:30:00" &&
   created().idem != r4a_lost.idem && sched_of(created()) == sched_of(r4a_lost))
ok("the new version says two reports may arrive",
   occursin(R4A_TWO, flat(body_of(created()))))
res = tick_at(DateTime(2033, 6, 9, 17, 31))
ok("once its send time is over the version is settled and the uncertain send time forgotten",
   :settled in res && !haskey(state(), "unsure"))

println("\n   A report sent on request says it too")
fresh_schedule!(DateTime(2033, 6, 9, 17, 30))
logged!(DateTime(2033, 6, 10, 10, 0), Date(2033, 6, 10))
LOSE_REPLY[] = true
tick_at(DateTime(2033, 6, 10, 17, 20); poked = true)
tick_at(DateTime(2033, 6, 10, 17, 29, 15); poked = true)
Notify.BACKOFF[] = nothing
res = tick_at(DateTime(2033, 6, 10, 17, 34); force = true)
now_d = r4a_made("ldgr-now-")
ok("a report sent on request after the send time carries the sentence",
   :sent in res && length(now_d) == 1 && occursin(R4A_AGAIN, flat(body_of(now_d[1]))))
ok("and the uncertain send time is forgotten", !haskey(state(), "unsure"))

println("\n   With nothing given up on, no version says any of it")
fresh_schedule!(DateTime(2033, 6, 11, 17, 30))
logged!(DateTime(2033, 6, 12, 10, 0), Date(2033, 6, 12))
tick_at(DateTime(2033, 6, 12, 10, 1))
ok("an ordinary scheduled version has neither sentence",
   length(CREATES) == 1 && !occursin("may repeat", body_of(created())) &&
   !occursin("may arrive", body_of(created())) && !haskey(state(), "unsure"))

# --- an unexpected error is said on the terminal once an hour ----------------
println("\n   An unexpected error: one warning on the terminal an hour, not one a beat")
fresh_schedule!(DateTime(2033, 6, 12, 17, 30))
Notify.LAST_UNEXPECTED[] = ("", DateTime(0))
tick_at(DateTime(2033, 6, 13, 8, 0))                           # a state file exists first
mkpath(statefile() * ".tmp")                                   # its temporary copy cannot be written
logged!(DateTime(2033, 6, 13, 8, 30), Date(2033, 6, 13))       # so the next hand-over must write it
const R4A_WORDS = "the daily report could not be prepared:"
# Case does not matter: the timer's and poke's own warning says "The daily report ...".
r4a_warned(cap) = count(r -> r.level == Logging.Warn && occursin(R4A_WORDS, lowercase(r.msg)), cap.recs)
r4a_inner(e) = e isa Notify.Reported ? e.error : e
n_a2 = count_of("email: " * R4A_WORDS, auditlog())
cap_a2 = Capture(Any[])
thrown_a2 = Any[]
# What the timer and poke do with whatever a tick throws.
r4a_beat(t; kw...) = try Notify.tick(at = t; kw...) catch e; push!(thrown_a2, e); Notify._warn_escaped(e) end
Logging.with_logger(cap_a2) do
    for m in 0:2
        r4a_beat(DateTime(2033, 6, 13, 9, m))
    end
end
ok("the tick throws for each of three beats, wrapping the original error",
   length(thrown_a2) == 3 && all(e -> e isa Notify.Reported && !(r4a_inner(e) isa Notify.Reported), thrown_a2))
ok("a Reported error prints as the error it wraps",
   sprint(showerror, thrown_a2[1]) == sprint(showerror, r4a_inner(thrown_a2[1])))
ok("the audit log has the sentence once",
   count_of("email: " * R4A_WORDS, auditlog()) == n_a2 + 1)
ok("and the terminal has it ONCE for the three beats ($(r4a_warned(cap_a2)) seen)", r4a_warned(cap_a2) == 1)
ok("the terminal's sentence never holds the key", !any(r -> leaks_key(r.msg), cap_a2.recs))
Logging.with_logger(cap_a2) do
    r4a_beat(DateTime(2033, 6, 13, 10, 5))
end
ok("an hour later it is said again, once, in both places",
   r4a_warned(cap_a2) == 2 && count_of("email: " * R4A_WORDS, auditlog()) == n_a2 + 2)
ok("the lock was let go each time: a tick can take it at once", trylock(Notify.BUSY) && (unlock(Notify.BUSY); true))

cap_esc = Capture(Any[])
Logging.with_logger(cap_esc) do
    Notify._warn_escaped(Notify.Reported(ErrorException("said already")))
    Notify._warn_escaped(ErrorException("nobody said this one $(KEY)"))
end
ok("an error that did not come through a tick's own catch is still warned about",
   length(cap_esc.recs) == 1 && occursin("nobody said this one", cap_esc.recs[1].msg))
ok("with the key taken out, and a Reported one left alone",
   !occursin(KEY, cap_esc.recs[1].msg) && !any(r -> occursin("said already", r.msg), cap_esc.recs))

# The scheduler's own entry points. poke runs the tick in a task of its own.
cap_poke = Capture(Any[])
Notify.SCHEDULE[] = Timer(3600)
Logging.with_logger(cap_poke) do
    Notify.poke()
    for _ in 1:100
        sleep(0.05)
        r4a_warned(cap_poke) >= 1 && break
    end
    sleep(0.5)
end
close(Notify.SCHEDULE[]); Notify.SCHEDULE[] = nothing
ok("a poke whose tick throws warns once (the tick's own), not twice ($(r4a_warned(cap_poke)) seen)",
   r4a_warned(cap_poke) == 1)
ok("and the lock is free after it", trylock(Notify.BUSY) && (unlock(Notify.BUSY); true))
rm(statefile() * ".tmp"; recursive = true, force = true)

println("\n   A failure that comes back after a tick that worked is written again")
fresh_schedule!(DateTime(2033, 6, 14, 17, 30))
Notify.LAST_UNEXPECTED[] = ("", DateTime(0))
tick_at(DateTime(2033, 6, 15, 8, 0))
mkpath(statefile() * ".tmp")
logged!(DateTime(2033, 6, 15, 8, 30), Date(2033, 6, 15))
n_r = count_of("email: " * R4A_WORDS, auditlog())
cap_r = Capture(Any[])
Logging.with_logger(cap_r) do
    r4a_beat(DateTime(2033, 6, 15, 9, 0))
end
ok("it fails and is written", count_of("email: " * R4A_WORDS, auditlog()) == n_r + 1 && r4a_warned(cap_r) == 1)
rm(statefile() * ".tmp"; recursive = true, force = true)
res = tick_at(DateTime(2033, 6, 15, 9, 10))
ok("the next tick works", res == [:scheduled, :cancelled])
ok("and forgets that failure (the reset is the tick's own, not done by hand)",
   Notify.LAST_UNEXPECTED[] == ("", DateTime(0)))
mkpath(statefile() * ".tmp")
logged!(DateTime(2033, 6, 15, 9, 15), Date(2033, 6, 15))
Logging.with_logger(cap_r) do
    r4a_beat(DateTime(2033, 6, 15, 9, 20))
end
ok("the same failure twenty minutes on, after a tick that worked, is written again, in both places",
   count_of("email: " * R4A_WORDS, auditlog()) == n_r + 2 && r4a_warned(cap_r) == 2)
rm(statefile() * ".tmp"; recursive = true, force = true)

# --- an audit line that could not be written is not counted as written -------
println("\n   An audit log that cannot be written, then can")
r4a_dir = joinpath(SCRATCH, "flush-dir"); mkpath(r4a_dir)
r4a_file = joinpath(SCRATCH, "flush-file.txt"); rm(r4a_file; force = true)
Notify.LAST_TROUBLE[] = ("a", now()); Notify.LAST_CANCEL_TROUBLE[] = ("b", now()); Notify.LAST_UNEXPECTED[] = ("c", now())
s_a3 = AuditSession(r4a_dir); log_event(s_a3, "something"; echo = false)
ok("a session with nothing to write has nothing to fail", Notify._flush_audit(AuditSession(r4a_dir)) === true)
ok("a throttle survives a flush that has nothing to write",
   Notify.LAST_TROUBLE[][1] == "a" && Notify.LAST_CANCEL_TROUBLE[][1] == "b" && Notify.LAST_UNEXPECTED[][1] == "c")
r4a_flush = Logging.with_logger(Logging.NullLogger()) do
    Notify._flush_audit(s_a3)
end
ok("a log that cannot be written says so, with false", r4a_flush === false)
ok("and all three throttles are forgotten",
   Notify.LAST_TROUBLE[] == ("", DateTime(0)) && Notify.LAST_CANCEL_TROUBLE[] == ("", DateTime(0)) &&
   Notify.LAST_UNEXPECTED[] == ("", DateTime(0)))
s_a3 = AuditSession(r4a_file); log_event(s_a3, "something"; echo = false)
ok("one that can be written says true", Notify._flush_audit(s_a3) === true && isfile(r4a_file))
rm(r4a_dir; recursive = true, force = true); rm(r4a_file; force = true)

fresh_schedule!(DateTime(2033, 6, 16, 17, 30))
logged!(DateTime(2033, 6, 17, 8, 0), Date(2033, 6, 17))
SEND_FAIL[] = Resend.Failure(:temporary, "The internet or Resend could not be reached: the connection " *
                                         "could not be opened. (test: audit log unwritable)", false)
r4a_audit = Layout.audit_log_path()
r4a_old = auditlog()
rm(r4a_audit; force = true); mkpath(r4a_audit)                 # the audit log is unwritable
cap_a3 = Capture(Any[])
res = Logging.with_logger(cap_a3) do
    tick_at(DateTime(2033, 6, 17, 9, 0))
end
rm(r4a_audit; recursive = true, force = true); write(r4a_audit, r4a_old)
ok("a failing tick while the audit log cannot be written is still a failing tick", res == [:failed])
ok("the terminal still hears about the failure, and about the log",
   any(r -> occursin("test: audit log unwritable", r.msg), cap_a3.recs) &&
   any(r -> occursin("The audit log could not be written.", r.msg), cap_a3.recs))
ok("the sentence was not counted as written", Notify.LAST_TROUBLE[] == ("", DateTime(0)))
ok("and it is not in the log (there was none)", count_of("(test: audit log unwritable)", auditlog()) == 0)
res = tick_at(DateTime(2033, 6, 17, 9, 6))
ok("the same failure six minutes later, with the log mended, is written", res == [:failed] &&
   count_of("(test: audit log unwritable)", auditlog()) == 1)
res = tick_at(DateTime(2033, 6, 17, 9, 12))
ok("and once it is written the once-an-hour rule holds again",
   res == [:failed] && count_of("(test: audit log unwritable)", auditlog()) == 1)
SEND_FAIL[] = nothing

# --- leave the world as later groups expect it -------------------------------
write(LOGP, R4A_LOG)
rm(statefile() * ".tmp"; recursive = true, force = true)
Notify.BACKOFF[] = nothing; Notify.CANCEL_BACKOFF[] = nothing
Notify.LAST_TROUBLE[] = ("", DateTime(0)); Notify.LAST_CANCEL_TROUBLE[] = ("", DateTime(0))
Notify.LAST_UNEXPECTED[] = ("", DateTime(0))
SEND_FAIL[] = nothing; CANCEL_FAIL[] = nothing; LOSE_REPLY[] = false
ok("nothing is left pending, the timer is off and the audit log is a file",
   Notify.SCHEDULE[] === nothing && isfile(Layout.audit_log_path()) && !isdir(statefile() * ".tmp"))

# =============================================================================
# 49. A day's session ends at midnight or at the send time, whichever is first
# =============================================================================
println("\n49. A correction made after the report went out is reported, even on the same date")

# Staff may correct a day freely while they are still counting it. A correction
# made after the send time that followed the first save is reported like a
# later-date one, because the owner has already been emailed the old figures: a
# shortage put right at 6 pm, after the 5:30 pm report, used to vanish. The rule
# is `Changes._session_over`. The saves here run at fixed moments in 2034
# (`after_save`'s `at`), write only the change log, and it is put back after.

const SNAP49 = logsnap()

println("\n   _session_over")
so(a, b; at = Time(17, 30)) = Changes._session_over(a, b, at)
const D49 = Date(2034, 3, 7)
t49(h, m = 0, s = 0; d = D49) = DateTime(d, Time(h, m, s))
ok("saved at 4 pm, corrected at 5 pm: free", !so(t49(16), t49(17)))
ok("saved at 4 pm, corrected at 6 pm, after the 5:30 pm report: reported", so(t49(16), t49(18)))
ok("saved at 6 pm, corrected at 11 pm: free", !so(t49(18), t49(23)))
ok("saved at 6 pm, corrected at 9 am the next day: reported", so(t49(18), t49(9; d = D49 + Day(1))))
ok("saved at 11:59 pm, corrected at 12:01 am: reported", so(t49(23, 59), t49(0, 1; d = D49 + Day(1))))
ok("an edit stamped 5:30:00 is in the same report as a save before it: free",
   !so(t49(17, 29, 59), t49(17, 30)) && !so(t49(17, 29, 59), t49(17, 30) + Millisecond(600)))
ok("one second later it is reported", so(t49(17, 29, 59), t49(17, 30, 1)))
ok("a day first saved at 5:30:00 is in that report, so a 5:31 pm edit is reported",
   so(t49(17, 30), t49(17, 31)))
ok("a day first saved at 5:30:01 is in the next one, so an 11 pm edit is free",
   !so(t49(17, 30, 1), t49(23)))
ok("the send time is the configured one: with 7 pm, a 6 pm edit is free",
   !so(t49(16), t49(18); at = Time(19)))
ok("with no send time, only midnight ends a session",
   !so(t49(16), t49(18); at = nothing) && so(t49(16), t49(9; d = D49 + Day(1)); at = nothing))

println("\n   The send time comes from Notify; the front doors do not pass it")
ok("Notify registered its send time with the change log",
   Changes.SEND_TIME[] !== nothing && Changes._registered_send_time() == Notify._send_time())
const KEEP49 = Changes.SEND_TIME[]
Changes.SEND_TIME[] = () -> error("boom")
ok("a send time that cannot be read leaves only midnight, and does not throw",
   Changes._registered_send_time() === nothing)
Changes.SEND_TIME[] = () -> "17:30"
ok("nor does one that is not a time", Changes._registered_send_time() === nothing)
Changes.SEND_TIME[] = KEEP49

println("\n   Through after_save and the report, at the configured send time")
const CUT49 = DateTime(D49, Notify._send_time())
rows49(d = D49) = filter(r -> r.day == d, Changes.rows_between(nothing, DateTime(2100, 1, 1)))
out49(journal, dv; d = D49, reason = "") =
    (ok = true, journal = journal, daily_ledger = "written", day_variance = dv,
     overnight_variance = NaN, reason = reason, opening_reason = "",
     released_days = [], date = d)
function was49(r, dv)
    p = DayRecord(r.date, copy(r.amounts), r.status, r.reason, r.opening_reason)
    p.amounts[:day_variance] = dv; p.amounts[:overnight_variance] = NaN
    return p
end
const NEW49 = (in_books = false, next_in_books = false, ledger_exists = false)
const OLD49 = (in_books = true,  next_in_books = false, ledger_exists = true)

r49a = day(D49; o = 1000.0, s = 500.0, c = 1200.0, reason = "Taxi fare paid from the drawer")
Changes.after_save(out49("added", -300.0; reason = r49a.reason); rec = r49a, before = NEW49,
                   at = CUT49 - Hour(1))
r49b = day(D49; o = 1000.0, s = 500.0, c = 1250.0, reason = "Taxi fare paid from the drawer")
Changes.after_save(out49("replaced", -250.0; reason = r49b.reason); rec = r49b,
                   previous = was49(r49a, -300.0), before = OLD49, at = CUT49 - Minute(30))
e49b = rows49()[end]
ok("a correction before the send time is free",
   length(rows49()) == 2 && e49b.what == "edited" && !e49b.cross_day_edit)
r49c = day(D49; o = 1000.0, s = 500.0, c = 1500.0)
Changes.after_save(out49("replaced", 0.0); rec = r49c, previous = was49(r49b, -250.0),
                   before = OLD49, at = CUT49 + Minute(40))
e49c = rows49()[end]
ok("one after the send time, on the same date, is reported, and it made the day balance",
   length(rows49()) == 3 && e49c.cross_day_edit && e49c.now_balances)

_, body49a = Notify.build_digest(CUT49 - Day(1), CUT49)
ent49 = section(body49a, "DAYS ENTERED")
ok("the report at the send time has the day as entered, the free correction folded in",
   occursin("7 March 2034", ent49) && occursin("Changed again by", ent49) &&
   !occursin("   Changed on", ent49))
_, body49b = Notify.build_digest(CUT49, CUT49 + Day(1))
chg49 = section(body49b, "CHANGES TO DAYS ALREADY SAVED")
ok("the next report names the correction made after it",
   occursin("7 March 2034 was changed on 7 March 2034.", chg49))
ok("with the time the day was first saved, since that was the same date",
   occursin("   It was first saved on 7 March 2034 at $(Notify._clock(CUT49 - Hour(1))).", chg49))
ok("and what moved, who did it and when",
   occursin("   Changed on 7 March 2034 by ", chg49) &&
   occursin(" at $(Notify._clock(CUT49 + Minute(40))):", chg49) &&
   occursin("1,250.00", chg49) && occursin("1,500.00", chg49))
ok("and that the day balances now, after the shortage the owner was told about",
   occursin("It did not balance before: shortage of \$250.00", chg49) &&
   occursin("It balances now.", chg49))

# A day typed after the send time: midnight comes first.
const D49B = Date(2034, 3, 9)
const CUT49B = DateTime(D49B, Notify._send_time())
Changes.after_save(out49("added", 0.0; d = D49B); rec = day(D49B), before = NEW49,
                   at = CUT49B + Minute(30))
Changes.after_save(out49("replaced", 0.0; d = D49B); rec = day(D49B; s = 100.0, c = 1100.0),
                   previous = was49(day(D49B), 0.0), before = OLD49, at = DateTime(D49B, Time(23)))
Changes.after_save(out49("replaced", 0.0; d = D49B); rec = day(D49B; s = 200.0, c = 1200.0),
                   previous = was49(day(D49B; s = 100.0, c = 1100.0), 0.0), before = OLD49,
                   at = DateTime(D49B + Day(1), Time(9)))
ok("a day typed after the send time may be corrected until midnight, freely",
   !rows49(D49B)[2].cross_day_edit)
ok("but a correction the next morning is reported", rows49(D49B)[3].cross_day_edit)

# With no send time to be had, a save still writes its row; only midnight counts.
const D49C = Date(2034, 3, 11)
Changes.SEND_TIME[] = () -> error("boom")
Changes.after_save(out49("added", 0.0; d = D49C); rec = day(D49C), before = NEW49,
                   at = t49(16; d = D49C))
Changes.after_save(out49("replaced", 0.0; d = D49C); rec = day(D49C; s = 100.0, c = 1100.0),
                   previous = was49(day(D49C), 0.0), before = OLD49, at = t49(18; d = D49C))
Changes.SEND_TIME[] = KEEP49
ok("a send time that cannot be read never stops a save's row being written",
   length(rows49(D49C)) == 2 && !rows49(D49C)[2].cross_day_edit)

write(LOGP, SNAP49)
ok("(the change log is put back)", logsnap() == SNAP49)

# =============================================================================
# 50. The key
# =============================================================================
println("\n50. The API key, after every failure above")

ok("THE API KEY IS NOWHERE IN THE AUDIT LOG", !occursin(KEY, auditlog()))
written = String[]
for (dir, _, fs) in walkdir(SCRATCH), f in fs
    local fp = joinpath(dir, f)
    fp == CONFIG && continue         # the settings file is where the key belongs
    push!(written, fp)
end
leaks = filter(p -> occursin(KEY, read(p, String)), written)
ok("nor in any other file this run wrote ($(length(written)) files)",
   isempty(leaks) || (println("      -> $leaks"); false))
ok("nor in any email handed over ($(length(ALL_CREATES)))",
   all(c -> !occursin(KEY, JSON3.write(c.email)) && !occursin(KEY, c.idem), ALL_CREATES))

# =============================================================================
# Helpers for groups 51 to 61 — the HTML body of the report (EmailHtml.jl)
# =============================================================================
# The plain text is pinned by every group above. These groups check that the
# HTML body shows the same facts, safely, in the order the design gives
# (handoff/email-html-design.md). The reports here are built from rows made in
# memory (`mkrow`) for days in 2035, plus the real books for the two things a
# report reads live: the ledgers still waiting and the balance the day before
# closed with.

const SNAP51 = logsnap()

"A change-log row with every cell chosen, for a report built without writing the log."
function mkrow(when::DateTime, d::Date; what = "saved", who = "tester", kind = "trading",
               day_diff = 0.0, night_diff = 0.0, reason = "", night_reason = "",
               was_day = NaN, was_night = NaN, changed = "", cross = false, pending = false,
               balances = false, gap = false, by = nothing)
    Changes.Row((when, who, what, d, kind,
                 what == "edited" ? "replaced" : what == "released" ? "" : "added", "written",
                 day_diff, night_diff, reason, night_reason, was_day, was_night, changed,
                 cross, pending, balances, gap, by))
end

"The report for these rows, as (subject, text, html)."
report(rows; problem = "", from = DateTime(2035, 3, 6, 17, 30), to = DateTime(2035, 3, 7, 17, 30),
       note = "", corrected = false) =
    Notify._report(Changes.Row[rows...], problem, from, to; note = note, corrected = corrected)

const D51 = Date(2035, 3, 7)
const W51 = DateTime(2035, 3, 7, 16, 0)

"The tags of an HTML document balance: every one opened is closed, in order."
function balanced_html(h::AbstractString)
    voids = Set(["meta", "br", "hr", "img", "input", "link"])
    stack = String[]
    for m in eachmatch(r"<(/?)([A-Za-z][A-Za-z0-9]*)\b[^>]*?(/?)>", h)
        tag = lowercase(m[2])
        (tag in voids || m[3] == "/") && continue
        if m[1] == "/"
            (isempty(stack) || pop!(stack) != tag) && return false
        else
            push!(stack, tag)
        end
    end
    return isempty(stack)
end

"What a person reads of an HTML body: tags gone, entities decoded, no-break spaces read as spaces, whitespace flattened."
function html_plain(h::AbstractString)
    t = String(h[first(findfirst("<body", h)):end])
    t = replace(t, r"<[^>]*>" => " ")
    t = replace(t, "&nbsp;" => " ", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&#39;" => "'")
    t = replace(t, r"&#(\d+);" => m -> string(Char(parse(Int, m[3:end-1]))))
    t = replace(t, "&amp;" => "&")
    return flat(t)
end

"The hidden preheader: the first element after <body>."
function preheader_of(h::AbstractString)
    m = match(r"<body[^>]*>\s*<div style=\"display:none;[^>]*>(.*?)</div>", h)
    return m === nothing ? nothing : String(m[1])
end

"Facts the text body prints that the HTML must show too: amounts, reasons, who, long dates."
function text_facts(text::AbstractString)
    flat_text = flat(text)
    amounts = unique(String[m.match for m in eachmatch(r"\$[0-9,]+\.[0-9]{2}", flat_text)])
    reasons = unique(String[String(strip(m[1])) for m in eachmatch(r"^\s+reason: (.+)$"m, text)])
    who = unique(String[String(m[1]) for m in eachmatch(r"(?:Entered|Changed again) by (.+?) at \d", flat_text)])
    append!(who, String[String(m[1]) for m in eachmatch(r"Changed on \d+ \w+ \d{4} by (.+?) at \d", flat_text)])
    dates = unique(String[m.match for m in eachmatch(
        r"\b\d{1,2} (?:January|February|March|April|May|June|July|August|September|October|November|December) \d{4}\b",
        flat_text)])
    return (amounts = amounts, reasons = reasons, who = unique(who), dates = dates)
end

"The HTML without its title and its hidden preheader: only what the reader sees."
unseen(h::AbstractString) = replace(replace(h, r"<title>.*?</title>"s => ""), preheader_of(h) => "")

"A long date of the text ('7 March 2035') is in the HTML's plain text, in full or, for the
report's own date, as the top line writes it ('07-03-2035')."
date_shown(d::AbstractString, plain::AbstractString) =
    occursin(d, plain) || occursin(Dates.format(Date(d, dateformat"d U yyyy"), "dd-mm-yyyy"), plain)

# The real books: what a report reads live.
const W51_WAITING = Chain.waiting_ledgers()
const PRIOR51 = Chain.prior_day(Date(2026, 2, 12))       # the Off day of group 13, closed with 3000

const HOSTILE51 = "<script>alert(1)</script> & \"quotes\" 'apostrophe'; semi; colons é — \U0001F600"
const HOSTILE51_ESCAPED = "&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quotes&quot; &#39;apostrophe&#39;; " *
                          "semi; colons é — \U0001F600"

# The corpus: (name, kwargs for `report`, rows).
const CORPUS51 = Any[
    ("quiet", (), Changes.Row[]),
    ("one balanced day", (), [mkrow(W51, D51; who = "reception")]),
    ("an Off day", (), [mkrow(W51, D51; kind = "closed")]),
    ("shortage and an opening that is less", (),
     [mkrow(W51, D51; who = "reception", day_diff = -1000.0, night_diff = -500.0,
            reason = "Paid the lab courier from the drawer; the receipt is in the folder.",
            night_reason = "Change fund moved to the safe overnight.")]),
    ("surplus and an opening that is more", (),
     [mkrow(W51, D51; day_diff = 250.0, night_diff = 100.0, reason = "A patient left change",
            night_reason = "")]),
    ("the day before is on record", (),
     [mkrow(W51, Date(2026, 2, 12); night_diff = -300.0, night_reason = "Float moved")]),
    ("a later edit that makes a day balance", (),
     [mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", who = "manager", cross = true,
            balances = true, was_day = 1000.0,
            changed = "POS Deposits To Scotiabank \$12,000.00 -> \$13,000.00; " *
                      "Taxi Fare (not counted) -> \$2,000.00; Reason \"Could not locate\" -> \"\"; " *
                      "Night reason \"\" -> \"Float moved\"; Kind of day trading -> closed")]),
    ("a pending-day edit", (),
     [mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 6)),
      mkrow(DateTime(2035, 3, 7, 9, 30), Date(2035, 3, 6); what = "edited", pending = true,
            changed = "Cash Sales \$500.00 -> \$700.00")]),
    ("a gap filled that releases a ledger", (),
     [mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 4); who = "manager", gap = true),
      mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 5); what = "released", by = Date(2035, 3, 4),
            day_diff = -200.0, night_diff = 500.0, reason = "Lab courier paid in cash.",
            night_reason = "Change fund moved")]),
    ("a gap filled with nothing to say", (),
     [mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 4); who = "manager", gap = true),
      mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 5); what = "released", by = Date(2035, 3, 4))]),
    ("same-date corrections only", (),
     [mkrow(DateTime(2035, 3, 7, 16, 0), D51; what = "edited")]),
    ("an unreadable log, quiet", (problem = "Line 3 of Change Log.csv (counting the heading as line 1) " *
                                            "could not be read and was left out.",), Changes.Row[]),
    ("an unreadable log, not quiet",
     (problem = "A line of the change log is damaged (for example a quotation mark that is never closed), " *
                "so none of it could be read.",), [mkrow(W51, D51)]),
    ("a late report over several days",
     (from = DateTime(2035, 3, 3, 17, 30), note = "This report is late: it could not be sent at 5:30 pm."),
     [mkrow(W51, D51)]),
    ("a corrected report", (corrected = true, note = "This replaces the report sent at 5:30 pm."),
     [mkrow(W51, D51)]),
    ("a hostile reason and name", (),
     [mkrow(W51, D51; who = "O'Brien <admin> & co", day_diff = -100.0, reason = HOSTILE51),
      mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 3); what = "edited", who = "O'Brien <admin> & co",
            cross = true, changed = "Reason \"\" -> \"$(HOSTILE51)\"")]),
]

# =============================================================================
# 51. The HTML and the text come from one report
# =============================================================================
println("\n51. The report in both forms")

ok("(the real books this group reads: a waiting list and the day before an Off day of 3000)",
   PRIOR51 !== nothing && PRIOR51.closing == 3000.0)

rows51 = [mkrow(W51, D51; day_diff = -1000.0, reason = "Short")]
s51, t51, h51 = report(rows51)
ok("_digest gives the first two values of _report, byte for byte",
   Notify._digest(Changes.Row[rows51...], "", DateTime(2035, 3, 6, 17, 30), DateTime(2035, 3, 7, 17, 30)) == (s51, t51))
ok("and build_report the same as build_digest with the HTML beside it, read from the log",
   (br51 = Notify.build_report(nothing, now()); bd51 = Notify.build_digest(nothing, now());
    length(br51) == 3 && br51[1:2] == bd51 && !isempty(br51[3])))
ok("with a corrected report and a note it is the same again",
   (cn = report(rows51; corrected = true, note = "N.");
    Notify._digest(Changes.Row[rows51...], "", DateTime(2035, 3, 6, 17, 30), DateTime(2035, 3, 7, 17, 30);
                   note = "N.", corrected = true) == cn[1:2]))
ok("the HTML is a page of its own", startswith(h51, "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">"))

# =============================================================================
# 52. The head of the page
# =============================================================================
println("\n52. Doctype, colour-scheme metas, title, preheader")

for (name, kw, rows) in CORPUS51
    local s, t, h = report(rows; kw...)
    ok("$(name): doctype, language, charset, viewport and both colour-scheme metas",
       startswith(h, "<!DOCTYPE html>") && occursin("<html lang=\"en\">", h) &&
       occursin("<meta charset=\"utf-8\">", h) &&
       occursin("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">", h) &&
       occursin("<meta name=\"color-scheme\" content=\"light dark\">", h) &&
       occursin("<meta name=\"supported-color-schemes\" content=\"light dark\">", h) &&
       occursin("<meta name=\"x-apple-disable-message-reformatting\">", h))
    ok("$(name): the title is the escaped subject", occursin("<title>$(Notify._e(s))</title>", h))
    ok("$(name): the preheader is the first thing after <body>, with the spacer after it",
       preheader_of(h) !== nothing &&
       occursin(r"<body[^>]*>\s*<div style=\"display:none;[^>]*>[^<]*</div>\s*<div style=\"display:none;max-height:0;overflow:hidden;mso-hide:all;\">(&#8199;&#847;){40}</div>", h))
end

s52a, t52a, h52a = report([mkrow(W51, D51; who = "reception", day_diff = -1000.0, reason = "Short"),
                           mkrow(W51 - Day(1), D51 - Day(1); day_diff = 50.0, reason = "Extra")])
ph52a = preheader_of(h52a)
ok("a report with differences: the counts, then the first two differences, newest first",
   ph52a !== nothing && startswith(ph52a, "2 days entered · 2 differences") &&
   occursin(" — CB Shortage (\$1,000.00) on 7&nbsp;March. CB Surplus \$50.00 on 6&nbsp;March.", ph52a))
s52b, t52b, h52b = report([mkrow(W51, D51; night_diff = -500.0, night_reason = "x")])
ok("an opening that is less reads as OB Shortage (\$500.00) on 7 March, worded as the tag is",
   occursin("OB Shortage (\$500.00) on 7&nbsp;March.", preheader_of(h52b)))
s52c, t52c, h52c = report(Changes.Row[])
ok("a quiet report's preheader is the quiet sentence the text prints",
   occursin("Nothing was entered or changed today, and every recorded day has its ledger.", preheader_of(h52c)) ||
   !isempty(W51_WAITING))
s52d, t52d, h52d = report(Changes.Row[]; problem = "Line 3 of Change Log.csv could not be read.")
ok("an unreadable log's preheader is the change-log sentence",
   preheader_of(h52d) == "THE CHANGE LOG COULD NOT BE READ PROPERLY, so this report may be missing entries. It is not a quiet day.")
s52e, t52e, h52e = report([mkrow(W51, D51)]; problem = "Line 3 of Change Log.csv could not be read.")
ok("and so is it when something was entered",
   startswith(preheader_of(h52e), "THE CHANGE LOG COULD NOT BE READ PROPERLY, so this report may be missing entries."))
ok("a quiet report with only same-date corrections says the text's sentence",
   occursin("Nothing new was entered, and every recorded day has its ledger.",
            preheader_of(report([mkrow(DateTime(2035, 3, 7, 16, 0), D51; what = "edited")])[3])) ||
   !isempty(W51_WAITING))

# =============================================================================
# 53. The banner, the heading, the notes
# =============================================================================
println("\n53. The unreadable-log banner, the heading, the notes")

pos(needle, h) = (r = findfirst(needle, h); r === nothing ? typemax(Int) : first(r))
ok("the unreadable-log warning is after the Days entered section, not above the band",
   pos("<strong class=\"ld\" style=\"color:#A63D40;\">THE CHANGE LOG COULD NOT BE READ PROPERLY,</strong>", h52e) >
   pos(">Days entered</span>", h52e) &&
   pos(">LDGR</span>", h52e) < pos("THE CHANGE LOG COULD NOT BE READ PROPERLY,</strong>", h52e))
ok("the warning is a danger card with its own stripe classes and both fills set",
   occursin("class=\"ldb lsd\" bgcolor=\"#FBEDE9\" style=\"background-color:#FBEDE9;border:1px solid #E9C3BE;border-left:4px solid #A63D40;", h52e))
ok("and it holds what could not be read, and what to do",
   occursin("Line 3 of Change Log.csv could not be read.", html_plain(h52e)) &&
   occursin("Ask whoever looks after ldgr to check \"Change Log.csv\" in the Records folder.", html_plain(h52e)))
ok("a readable log has no warning", !occursin("class=\"ldb lsd\"", h51))
ok("the title band is one row: LDGR | Daily Report | 07-03-2035, with no (Urgent Care)",
   occursin("LDGR | Daily Report | 07-03-2035", html_plain(h51)) && !occursin("Urgent Care", h51) && !occursin("<h1", h51) &&
   occursin("white-space:nowrap;color:#FFFFFF;\"><span style=\"color:#FFFFFF;font-weight:700;\">LDGR</span>", h51))
_, _, hc51 = report([mkrow(W51, D51)]; corrected = true, note = "This replaces the report sent at 5:30 pm.")
ok("a corrected report says so in the band",
   occursin("LDGR | Corrected Report | 07-03-2035", html_plain(hc51)) && !occursin("Daily Report", hc51))
ok("the caption of how current the report is stays, on the 24-hour clock; there is no Covering line",
   !occursin("Covering", h51) && occursin(">Includes everything saved up to 16:00 on 7&nbsp;March.</div>", h51))
ok("a report with nothing in it has no 'Includes everything' line", !occursin("Includes everything", h52c))
ok("a note is plain soft text in parentheses, with the time kept together and no grey box",
   occursin("(This replaces the report sent at 17:30.)</div>", hc51) && !occursin("class=\"lq li\"", hc51) &&
   !occursin("border-radius:10px", hc51))
ok("the note sits under the caption, aligned with it (the same cell)",
   pos(">Includes everything saved up to", hc51) < pos("(This replaces the report", hc51) &&
   occursin(r"Includes everything saved up to[^\n]*</div>\n<div class=\"ls\"[^\n]*>\(This replaces"s, hc51))
_, _, hs51 = report([mkrow(W51, D51)]; from = DateTime(2035, 3, 3, 17, 30), note = "Late.")
ok("a report over several days has no several-days paragraph", !occursin("This report covers more than one day", hs51) &&
   !occursin("on the days in between", hs51) && occursin("(Late.)", hs51))
_, _, hl51 = report([mkrow(W51, D51)]; from = DateTime(2035, 3, 3, 17, 30),
                    note = "This report is late: it could not be sent at 5:30 pm, usually because ldgr was closed or offline before it could hand the report over.")
ok("the late note is dropped from the HTML (the text keeps it), and nothing is left in its place",
   !occursin("This report is late", hl51) && !occursin("()", hl51) && !occursin(">(", hl51))
_, _, hl51b = report([mkrow(W51, D51)];
                     note = "This report is late: it could not be sent at 5:30 pm, usually because ldgr was closed or offline. The computer's clock was behind, at 5:42 pm.")
ok("when a late note is joined to another note only the late sentence goes", !occursin("This report is late", hl51b) &&
   occursin("The computer's clock was behind, at 17:42.", html_plain(hl51b)))
_, _, hr51 = report([mkrow(W51, D51)]; note = "This report may repeat one sent at 5:30 pm: ldgr could not confirm that Resend had received it.")
ok("a possible-repeat note is shown, in parentheses",
   occursin("(This report may repeat one sent at 17:30: ldgr could not confirm that Resend had received it.)", html_plain(hr51)))
_, _, hf51 = report([mkrow(W51, D51)]; note = "This follows the report sent at 5:30 pm. When ldgr checked it afterwards, part of the change log could not be read.")
ok("a follow-up note is shown, in parentheses", occursin("(This follows the report sent at 17:30.", html_plain(hf51)))
_, _, hfr51 = report([mkrow(W51, D51)]; note = "This is the first report since email was set up, so it covers everything up to 5:30 pm on 7 March 2035.")
ok("a first-report note is shown, in parentheses", occursin("(This is the first report since email was set up", html_plain(hfr51)))
ok("no note and one day: no parenthesised line", !occursin(">(", h51))

# =============================================================================
# 54. Escaping
# =============================================================================
println("\n54. Nothing typed reaches the page raw")

s54, t54, h54 = report(CORPUS51[end][3])
ok("a hostile reason never appears raw", !occursin("<script>", h54) && !occursin("alert(1)</script>", h54))
ok("its escaped form does, in the day's reason box and in the edit that repeats it",
   count_of(HOSTILE51_ESCAPED, h54) >= 1 && occursin("&lt;script&gt;alert(1)&lt;/script&gt;", h54))
ok("the name is escaped too", occursin("O&#39;Brien &lt;admin&gt; &amp; co", h54) && !occursin("<admin>", h54))
ok("the text body still has it raw, as before", occursin("reason: " * HOSTILE51, t54))
ok("a reason whose text contains '; ' is split into parts and none is dropped (the text does the same)",
   occursin("semi", html_plain(h54)) && occursin("colons é — 😀", html_plain(h54)))
ok("_e escapes all five characters, and the subject goes into the title through it",
   Notify._e("a<b>&\"'") == "a&lt;b&gt;&amp;&quot;&#39;" && occursin("<title>$(Notify._e(s54))</title>", h54))
hp54 = report([mkrow(W51, D51)]; problem = "Line 3 <b>\"x\"</b> & co.")[3]
ok("a problem with markup in it is escaped", !occursin("<b>\"x\"</b>", hp54) && occursin("&lt;b&gt;&quot;x&quot;&lt;/b&gt; &amp; co.", hp54))

# =============================================================================
# 55. Wording, colour and edits
# =============================================================================
println("\n55. No warning codes, every fill set twice, and what an edit looks like")

"Every `td`, `table` and `body` that sets a `background-color` also has the same `bgcolor` attribute."
function fills_ok(h::AbstractString)
    for m in eachmatch(r"<(td|table|body)\b[^>]*>", h)
        tag = m.match
        c = match(r"(?<![-\w])background-color:(#[0-9A-Fa-f]{6})", tag)
        c === nothing && continue
        occursin("bgcolor=\"$(c[1])\"", tag) || return false
    end
    return true
end

for (name, kw, rows) in CORPUS51
    local s, t, h = report(rows; kw...)
    ok("$(name): no warning codes, no words the report never uses",
       !occursin(r"\bL[1-3]-[A-Z]\b", h) && !occursin("trading", html_plain(h)))
    ok("$(name): tags balance", balanced_html(h))
    ok("$(name): two builds are byte-identical", report(rows; kw...) == (s, t, h))
    ok("$(name): every element carries its own style (no cell, block or span without one)",
       !occursin(r"<(td|div|span|p|h1)(?![^>]*style=)[^>]*>", h))
    ok("$(name): no fill is set with the background shorthand, anywhere (the style block included)",
       !occursin(r"(?<![-\w])background:", h))
    ok("$(name): every cell, table and the body that has a fill also has its bgcolor, the band's included",
       fills_ok(h) && occursin("bgcolor=\"#1F6F5C\"", h))
end

# A day whose kind changed: only the Day type row, no figures, differences or explanations.
_, _, h55 = report(CORPUS51[7][3])
ok("an edit has no ASCII arrow; a struck-through before value sits in <s>",
   !occursin("->", h55) && occursin("<s>Work day</s>", h55))
ok("a kind-of-day change shows ONLY the row Day type | Work day | Off day",
   occursin(">Day type</td>", h55) && occursin(">Off day</td>", h55) && !occursin(">closed<", h55) &&
   count_of("<tr><td class=\"li lr\"", h55) == 1 &&
   !occursin("12,000.00", h55) && !occursin("13,000.00", h55) && !occursin("(not counted)", h55) &&
   !occursin("Float moved", h55) && !occursin("Explanation", h55) && !occursin("CB ", html_plain(h55)))
ok("and its one tag is Work status update, with no Balanced or Numbers revised",
   count_of(">Work status update</span>", h55) == 1 && !occursin(">Balanced</span>", h55) &&
   !occursin(">Numbers revised</span>", h55) && !occursin("Previously Not Balanced", h55))
ok("BEFORE and AFTER column heads appear once, above the row",
   count_of(">Before</td>", h55) == 1 && count_of(">After</td>", h55) == 1)
ok("the bullet names who and when, with the date as dd-mm-yyyy and the 24-hour clock",
   occursin("Changed on 07-03-2035 by manager at 10:05", h55) && !occursin("10:05&nbsp;am", h55))

# An edit that cleared a difference.
D55 = Date(2035, 3, 2)
_, _, hcl = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", who = "manager", cross = true, balances = true,
                          was_day = -2000.0, changed = "Closing Balance \$18,000.00 -> \$20,000.00; Reason \"Could not locate\" -> \"\"")])
ok("a cleared difference: Balanced, with (Previously Not Balanced) after the date",
   occursin(">Balanced</span>", hcl) && !occursin(">Numbers revised</span>", hcl) &&
   occursin(r"2&nbsp;March 2035 <span[^>]*>\(Previously&nbsp;Not&nbsp;Balanced\)</span>", hcl))
ok("the table has the figure and the difference row: CB Shortage | (\$2,000.00) | \$0.00",
   occursin(">Closing Balance</td>", hcl) && occursin("<s>\$18,000.00</s>", hcl) &&
   occursin(r">CB Shortage</td><td[^>]*><s>\(\$2,000\.00\)</s></td><td[^>]*>\$0\.00</td>", hcl))
ok("an explanation that was cleared has no row (the first-save sentence shows it)",
   !occursin(">Explanation<", hcl) && !occursin("Could not locate", hcl))
ok("and there is no 'It did not balance before' sentence in the HTML", !occursin("did not balance before", html_plain(hcl)))

# An edit that made a balanced day short: Numbers revised only, a new difference row, the explanation added.
_, _, hns = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", who = "manager", cross = true,
                          day_diff = -1000.0, was_day = 0.0, reason = "Counted again",
                          changed = "Closing Balance \$20,000.00 -> \$19,000.00; Reason \"\" -> \"Counted again\"")])
ok("a day still or newly unbalanced after a reported edit is Numbers revised, and nothing else",
   occursin(">Numbers revised</span>", hns) && !occursin(">Balanced</span>", hns) && !occursin(">CB Shortage (", hns) &&
   !occursin("Previously Not Balanced", hns))
ok("the new difference is a row: CB Shortage | \$0.00 | (\$1,000.00)",
   occursin(r">CB Shortage</td><td[^>]*><s>\$0\.00</s></td><td[^>]*>\(\$1,000\.00\)</td>", hns))
ok("an explanation that was added is kept: Explanation, Before (none), After the words",
   occursin(">Explanation</div>", hns) && occursin("(none)", hns) && occursin("<strong>Counted again</strong>", hns))
ok("the row labels are Explanation and OB explanation, never Reason or Opening reason",
   !occursin(">Reason</div>", hns) && !occursin("Opening reason", hns) &&
   occursin(">OB explanation</div>", report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", cross = true,
                                                  changed = "Night reason \"a\" -> \"b\"")])[3]))

# The difference row's label, and its values.
function diff_row(was, now, kw = :day)
    h = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", cross = true,
                      (kw === :day ? (was_day = was, day_diff = now) : (was_night = was, night_diff = now))...,
                      changed = "Cash Sales \$1.00 -> \$2.00")])[3]
    m = match(r"<td class=\"li lr\"[^>]*>((?:CB|OB) [A-Za-z]+)</td><td[^>]*><s>([^<]*)</s></td><td[^>]*>([^<]*)</td>", h)
    return m === nothing ? nothing : (String(m[1]), String(m[2]), String(m[3]))
end
ok("both sides a shortage, or one of them nothing: CB Shortage",
   diff_row(-2000.0, -1000.0) == ("CB Shortage", "(\$2,000.00)", "(\$1,000.00)") &&
   diff_row(-1000.0, 0.0) == ("CB Shortage", "(\$1,000.00)", "\$0.00") &&
   diff_row(0.0, -1000.0) == ("CB Shortage", "\$0.00", "(\$1,000.00)"))
ok("both sides a surplus, or one of them nothing: CB Surplus, plain figures",
   diff_row(1000.0, 500.0) == ("CB Surplus", "\$1,000.00", "\$500.00") &&
   diff_row(0.0, 500.0) == ("CB Surplus", "\$0.00", "\$500.00"))
ok("a shortage turned into a surplus: CB Difference", diff_row(-1000.0, 500.0) == ("CB Difference", "(\$1,000.00)", "\$500.00"))
ok("the opening difference is worded the same with OB, a less opening being a shortage",
   diff_row(-300.0, 0.0, :night) == ("OB Shortage", "(\$300.00)", "\$0.00") &&
   diff_row(100.0, 300.0, :night) == ("OB Surplus", "\$100.00", "\$300.00") &&
   diff_row(-100.0, 300.0, :night) == ("OB Difference", "(\$100.00)", "\$300.00"))
ok("an edit that left both differences as they were has no difference row",
   diff_row(-1000.0, -1000.0) === nothing && diff_row(NaN, 0.0) === nothing)

# Several reported edits: a table each, with a caption.
_, _, h2e = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", who = "manager", cross = true, day_diff = -1000.0,
                          was_day = 0.0, reason = "x", changed = "Closing Balance \$20,000.00 -> \$19,000.00; Reason \"\" -> \"x\""),
                    mkrow(DateTime(2035, 3, 7, 11, 5), D55; what = "edited", who = "boss", cross = true, day_diff = 500.0,
                          was_day = -1000.0, reason = "y", changed = "Closing Balance \$19,000.00 -> \$20,500.00; Reason \"x\" -> \"y\"")])
ok("with two reported edits there are two tables, each under a caption of its own",
   count_of("Changed on 07-03-2035 at 10:05</div>", h2e) == 1 && count_of("Changed on 07-03-2035 at 11:05</div>", h2e) == 1 &&
   count_of(">Before</td>", h2e) == 2)
ok("and one bullet per edit, naming who and when",
   occursin("Changed on 07-03-2035 by manager at 10:05", h2e) && occursin("Changed on 07-03-2035 by boss at 11:05", h2e) &&
   occursin(">CB Difference</td>", h2e))
ok("a single edit's table has no caption", !occursin("at 10:05</div>", hcl))

# Figures that were not counted, an unreadable part, an edit that moved nothing.
_, _, hnc = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", cross = true,
                          changed = "Taxi Fare (not counted) -> \$2,000.00; Doctor's Fees \$10.00 -> (not counted)")])
ok("a figure that was not counted is struck through, and the label stays as written",
   occursin("<s>(not counted)</s>", hnc) && occursin(">\$2,000.00</td>", hnc) && occursin("<s>\$10.00</s>", hnc) &&
   occursin(">(not counted)</td>", hnc) && occursin(">Doctor&#39;s Fees</td>", hnc))
_, _, hu55 = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", cross = true,
                           changed = "Something the report cannot parse <b>; Reason \"a\" -> \"b\"; Taxi Fare \$1.00 -> \$2.00")])
ok("a part the layout cannot read is shown as it stands, escaped, and the others still are",
   occursin("Something the report cannot parse &lt;b&gt;", hu55) && occursin("<s>a</s>", hu55) &&
   occursin("<strong>b</strong>", hu55) && occursin("<s>\$1.00</s>", hu55))
_, _, hn55 = report([mkrow(DateTime(2035, 3, 7, 10, 5), D55; what = "edited", cross = true)])
ok("an edit with no figure different says so on its bullet and has no table",
   occursin("by tester at 10:05, with no figure different", hn55) && !occursin(">Before</td>", hn55))

# The tags of a day's own state, with their amounts in words.
_, _, hd55 = report(CORPUS51[4][3])
ok("OB Shortage (\$500.00) and CB Shortage (\$1,000.00) are red tags, the opening above the closing",
   occursin(">OB Shortage (\$500.00)</span>", hd55) && occursin(">CB Shortage (\$1,000.00)</span>", hd55) &&
   pos(">OB Shortage", hd55) < pos(">CB Shortage", hd55) && count_of("class=\"ld ldb\"", hd55) == 2)
ok("a surplus is plain and amber: CB Surplus \$250.00, OB Surplus \$100.00",
   (hh = report(CORPUS51[5][3])[3]; occursin(">CB Surplus \$250.00</span>", hh) && occursin(">OB Surplus \$100.00</span>", hh) &&
                                    count_of("class=\"lw lwb\"", hh) == 2 && pos(">OB Surplus", hh) < pos(">CB Surplus", hh)))
ok("a balanced day is a green Balanced tag, an Off day a neutral one",
   occursin("class=\"la lb\"", report([mkrow(W51, D51)])[3]) && occursin(">Balanced</span>", report([mkrow(W51, D51)])[3]) &&
   occursin("class=\"ls lq\"", report([mkrow(W51, D51; kind = "closed")])[3]) &&
   occursin(">Off day</span>", report([mkrow(W51, D51; kind = "closed")])[3]))
ok("the tags never wrap and carry background-color on the span",
   all(m -> occursin("white-space:nowrap", m.match) && occursin("background-color:#", m.match),
       eachmatch(r"<span class=\"l[a-z] l[a-z]+\"[^>]*>", hd55)))
ok("a difference's explanation is on the bullet, in the left column, never in the tag column",
   occursin("entered and saved by reception with explanations: OB &ndash; Change fund moved to the safe overnight.; CB &ndash; Paid the lab courier from the drawer; the receipt is in the folder.", hd55) &&
   !occursin("Reason:", hd55) && !occursin("During the day", hd55) && !occursin("Opening balance", hd55))
ok("none of the old card furniture is left: no last-close line, no coloured stripe",
   !occursin("than the day before closed with", hd55) && !occursin("border-left:4px", hd55))
ok("one explanation reads: with explanation: …, and no explanation given when it is empty",
   occursin("entered and saved by tester with explanation: Short</td>", report([mkrow(W51, D51; day_diff = -1000.0, reason = "Short")])[3]) &&
   occursin("entered and saved by tester, no explanation given</td>", report([mkrow(W51, D51; day_diff = 5.0)])[3]))
ok("two differences with one empty: that one says no explanation given",
   occursin("with explanations: OB &ndash; Float; CB &ndash; no explanation given",
            report([mkrow(W51, D51; day_diff = -5.0, night_diff = 3.0, night_reason = "Float")])[3]))
ok("the opening's comparison with the day before's close is not in the HTML (the text keeps it)",
   !occursin("the day before closed with", report(CORPUS51[6][3])[3]) &&
   occursin("than the \$3,000.00 the day before closed with.", report(CORPUS51[6][3])[2]))

# A gap filled that releases a ledger.
ok("a gap day: its suffix, its bullet and a Ledger made line with each difference and its explanation",
   (hg = report(CORPUS51[9][3])[3];
    occursin("4&nbsp;March 2035 <span", hg) && occursin("(Previous&nbsp;Gap&nbsp;Day)", hg) &&
    occursin("&#10003; Ledger made for 5&nbsp;March 2035</div>", hg) &&
    occursin(">OB Surplus \$500.00</span>", hg) && occursin(">CB Shortage (\$200.00)</span>", hg) &&
    occursin(">OB explanation: Change fund moved</div>", hg) && occursin(">CB explanation: Lab courier paid in cash.</div>", hg) &&
    !occursin("filling a gap", hg)))
rel_rows(reason) = [mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 4); who = "manager", gap = true),
                    mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 5); what = "released", by = Date(2035, 3, 4),
                          day_diff = -200.0, reason = reason)]
ok("a released day with one difference says 'explanation: …', and with none says no explanation given",
   occursin(">explanation: x</div>", report(rel_rows("x"))[3]) &&
   occursin(">no explanation given</div>", report(rel_rows(""))[3]))
ok("a gap with nothing to say has the Ledger made line and no tag row under it",
   (hq = report(CORPUS51[10][3])[3]; occursin("&#10003; Ledger made for 5&nbsp;March 2035</div>", hq) &&
                                      !occursin("font-size:12px;line-height:16px", hq)))

# =============================================================================
# 56. One section of days, newest first
# =============================================================================
println("\n56. Days entered is the only day section, newest date first")

_, _, h56 = report([mkrow(W51 - Day(2), D51 - Day(2); day_diff = -50.0, reason = "Short"),
                    mkrow(W51, D51, who = "reception")])
ok("a newer balanced day comes before an older day with a difference, both cards under one heading",
   count_of(">Days entered</span>", h56) == 1 &&
   pos("7&nbsp;March 2035", h56) < pos("5&nbsp;March 2035", h56))
ok("every day is a card of one shape: a date, its bullets and its tags, never a compact row",
   count_of("class=\"lc\" bgcolor=\"#FFFFFF\"", h56) == 2 && occursin(">Balanced</span>", h56) &&
   occursin(">CB Shortage (\$50.00)</span>", h56))
for (name, kw, rows) in CORPUS51
    local h = report(rows; kw...)[3]
    ok("$(name): there is no Needs attention heading, no Gaps filled heading and no Changes heading",
       !occursin("Needs attention", h) && !occursin("Gaps filled", h) && !occursin("Gaps Filled", h) &&
       !occursin("Changes to days", h) && !occursin("Ledgers still waiting", h))
end
ok("a gap filled and an earlier day changed are cards in the same section, newest first",
   (hq = report(vcat(CORPUS51[10][3], [mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                                              changed = "Cash Sales \$1.00 -> \$2.00")]))[3];
    count_of(">Days entered</span>", hq) == 1 && pos("4&nbsp;March 2035", hq) < pos("2&nbsp;March 2035", hq)))
ok("a day with a reported edit and a day that was only entered sit side by side: no separate heading",
   (hs = report([mkrow(W51, D51; day_diff = -1.0, reason = "x"),
                 mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true)]);
    count_of(">Days entered</span>", hs[3]) == 1 &&
    startswith(preheader_of(hs[3]), "1 day entered · 1 difference · 1 day changed")))
ok("a day with a reported edit and no figure different still has its card and a Numbers revised tag",
   occursin(">Numbers revised</span>", report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true)])[3]))
ok("there is no summary card: the counts live in the preheader alone",
   !occursin("1 day entered", unseen(hs[3])) && !occursin("font-size:16px;line-height:24px;font-weight:600", hs[3]))
if isempty(W51_WAITING)
    ok("nothing waiting, no pending section", !occursin("Saved Days with Pending Ledgers", h56))
end

# =============================================================================
# 57. Quiet cases, parity, size
# =============================================================================
println("\n57. Quiet reports, nothing lost (but for what the owner chose to leave out), and the size")

if isempty(W51_WAITING)
    _, tq, hq = report(Changes.Row[])
    ok("no rows, nothing waiting: the quiet sentence and a tick",
       occursin("Nothing was entered or changed today, and every recorded day has its ledger.", html_plain(hq)) &&
       occursin("<span class=\"la\" style=\"color:#1F6F5C;font-weight:700;\">&#10003;</span>", hq) &&
       occursin("class=\"lc\" bgcolor=\"#FFFFFF\" style=\"background-color:#FFFFFF;", hq))
    _, _, hs = report([mkrow(DateTime(2035, 3, 7, 16, 0), D51; what = "edited")])
    ok("same-date corrections only: the text's sentence and no tick",
       occursin("Nothing new was entered, and every recorded day has its ledger.", html_plain(hs)) &&
       !occursin("&#10003;", hs))
    _, _, hus = report(Changes.Row[]; problem = "Line 3 of Change Log.csv could not be read.")
    ok("an unreadable log and nothing else: no summary card and no tick, never an all-clear",
       !occursin("&#10003;", hus) && !occursin("font-size:16px;line-height:24px;font-weight:600", hus) &&
       !occursin("Nothing was entered", html_plain(hus)))
    ok("its warning is still there, and no Days entered heading", occursin("THE CHANGE LOG COULD NOT BE READ PROPERLY,", hus) &&
       !occursin("Days entered", hus))
    ok("a quiet span says 'Nothing was entered or changed, and'",
       occursin("Nothing was entered or changed, and every recorded day has its ledger.",
                html_plain(report(Changes.Row[]; from = DateTime(2035, 3, 3, 17, 30))[3])))
else
    ok("(the books hold waiting ledgers, so the quiet-report checks are done by group 12's rule)", true)
end

"""
The text with what the HTML deliberately no longer shows taken out, so the parity check
below keeps checking everything else. EXACTLY the owner's list (handoff/email-html-round2.md,
"Facts the HTML deliberately no longer shows"):

  1. the last-close amount: "than the \$20,000.00 the day before closed with" (and, for a
     released day, "that 5 March 2035 closed with");
  2. the late and several-days notes;
  3. a cleared explanation's table row (it is a part of an edit, which the facts below do
     not read; the first-save sentence shows the old explanation instead);
  4. the figures of a day whose kind changed: every part of an edit block, and the
     "It did not balance before" line under it, in the paragraph of a day with a
     `Kind of day` part (that day is tagged Work status update and shows only its Day
     type row);
  5. the Records folder line;
  6. every intermediate "Changed again" save but the last (the text prints only the last).
"""
function parity_text(t::AbstractString)
    t = replace(t, r"the\s+\$[0-9,]+\.[0-9]{2}\s+(?:the\s+day\s+before|that\s+\d+\s+\w+\s+\d{4})\s+closed\s+with" => "")  # 1
    t = replace(t, r"This report is late:[^\n]*(?:\n[^\n]+)*\n" => "")                                                # 2
    t = replace(t, r"This report covers more than one day:[^\n]*(?:\n[^\n]+)*\n" => "")                               # 2
    t = join((occursin("Kind of day", para) ?
                  replace(replace(para, r"(   Changed on [^\n]*:\n)((?:      [^\n]*\n)+)" => s"\1"),
                          r"   It did not balance before:[^\n]*\n" => "") : para
              for para in split(t, "\n\n")), "\n\n")                                                                # 4
    t = replace(t, r"Records folder: [^\n]*\n" => "")                                                                # 5
    return t
end

println("\n   Every fact the text prints is in the HTML")
for (name, kw, rows) in CORPUS51
    local s, t, h = report(rows; kw...)
    local plain = html_plain(h)
    local f = text_facts(parity_text(t))
    ok("$(name): every amount ($(length(f.amounts))), explanation ($(length(f.reasons))), name ($(length(f.who))) and date ($(length(f.dates)))",
       all(a -> occursin(a, plain), f.amounts) && all(r -> r == "(none given)" || occursin(r, plain), f.reasons) &&
       (!("(none given)" in f.reasons) || occursin("no explanation given", plain)) &&
       all(w -> occursin(w, plain), f.who) && all(d -> date_shown(d, plain), f.dates))
    ok("$(name): the HTML has the credit and no Records folder; the text keeps the footer and the folder",
       occursin("Powered by SolRegia", plain) && !occursin("Records folder:", plain) &&
       occursin("This report is sent at 5:30 pm on each day ldgr is used.", t) &&
       occursin("Records folder: " * Layout.ROOT, t))
end
ok("the parity check has teeth: with an amount taken out of the HTML it would be found",
   let (_, t, h) = report(CORPUS51[4][3])
       pl = html_plain(h)
       occursin("\$500.00", pl) && !all(a -> occursin(a, replace(pl, "\$500.00" => "")), text_facts(t).amounts)
   end)
println("\n   The omissions are exactly the ones the owner listed, and are real")
let (_, t6, h6) = report(CORPUS51[6][3]), (_, t7, h7) = report(CORPUS51[7][3])
    p6, p7 = html_plain(h6), html_plain(h7)
    ok("the last-close amount is in the text and not in the HTML, and the parity text drops it",
       occursin("the day before closed with", t6) && !occursin("the day before closed with", p6) &&
       "\$3,000.00" in text_facts(t6).amounts && !("\$3,000.00" in text_facts(parity_text(t6)).amounts) &&
       !occursin("\$3,000.00", p6))
    gone7 = setdiff(text_facts(t7).amounts, text_facts(parity_text(t7)).amounts)
    ok("the figures of a day whose kind changed are in the text and not in the HTML ($(length(gone7)) amounts)",
       !isempty(gone7) && all(a -> !occursin(a, p7), gone7) && !occursin("Kind of day", parity_text(t7)) &&
       occursin("Work day -> Off day", t7) && occursin("Day type", p7))
end
ok("the late and several-days notes are in the text and not in the HTML",
   let (_, tl, hl) = report([mkrow(W51, D51)]; from = DateTime(2035, 3, 3, 17, 30),
                            note = "This report is late: it could not be sent at 5:30 pm, usually because ldgr was closed.")
       occursin("This report is late", tl) && occursin("This report covers more than one day", tl) &&
       !occursin("This report is late", hl) && !occursin("covers more than one day", hl) &&
       !occursin("This report is late", parity_text(tl)) && !occursin("covers more than one day", parity_text(tl))
   end)
ok("a cleared explanation is in the text's edit and not in the HTML's table, and the parity text keeps the rest",
   let (_, tc, hc) = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                                   changed = "Closing Balance \$18,000.00 -> \$20,000.00; Reason \"Could not locate\" -> \"\"")])
       occursin("Could not locate", tc) && !occursin("Could not locate", hc) && occursin("\$20,000.00", html_plain(hc))
   end)

println("\n   Size")
_, _, h1day = report([mkrow(W51, D51; day_diff = -1000.0, night_diff = -500.0, reason = "Paid the courier",
                            night_reason = "Float")])
ok("a one-day report is under 30 KB ($(length(codeunits(h1day))) bytes)", length(codeunits(h1day)) < 30_000)
days31 = [mkrow(DateTime(2035, 2, 1, 16, 0) + Day(i), Date(2035, 2, 1) + Day(i); who = "reception") for i in 0:30]
_, _, h31 = report(days31; from = DateTime(2035, 1, 31, 17, 30), to = DateTime(2035, 3, 3, 17, 30))
ok("31 balanced days are under 100 KB ($(length(codeunits(h31))) bytes)", length(codeunits(h31)) < 100_000)
ok("and every one of them is there", count_of(">Balanced</span>", h31) == 31 && balanced_html(h31))
ok("a report with nothing in it is small ($(length(codeunits(h52c))) bytes)", length(codeunits(h52c)) < 12_000)

# =============================================================================
# 58. A ledger that is waiting
# =============================================================================
println("\n58. Saved Days with Pending Ledgers, on the page")

# A real save into the books: a day in August 2026 whose day before is missing, so its
# ledger is held. It stays in the books for the groups after this one.
save(day(Date(2026, 8, 20); o = 1000.0, s = 500.0, c = 1500.0))
W58 = Chain.waiting_ledgers()
ok("(the books now hold a waiting ledger: 20 August 2026, waiting for the 19th)", W58 == [Date(2026, 8, 20)])
s58a, t58a, h58a = report(Changes.Row[])
ok("nothing entered but a ledger waiting is not a quiet report: no tick, no quiet sentence, the section",
   !occursin("&#10003;", h58a) && !occursin("Nothing was entered", html_plain(h58a)) &&
   occursin(">Saved Days with Pending Ledgers</span>", h58a) && !occursin("Ledgers still waiting", h58a))
ok("it is one card: the date bold on its own line, the caption under it, a real line break between them",
   occursin("20&nbsp;August 2026</span><br>\n<span class=\"ls\" style=\"font-size:14px;line-height:20px;color:#5B6660;\">" *
            "Saved, but its ledger cannot be made until 19&nbsp;August 2026 is entered.</span>", h58a) &&
   !occursin("2026Saved", replace(h58a, r"<[^>]*>" => "")) && occursin("font-weight:700;color:#1C2521;\">20&nbsp;August 2026</span>", h58a))
ok("the closing sentence is at the very bottom of the card, soft and 12px; the old three lines are gone",
   occursin(">This list clears automatically as gap dates are filled in.</div>", h58a) &&
   occursin("font-size:12px;line-height:18px;color:#5B6660;\">This list clears", h58a) &&
   pos("2026 is entered.", h58a) < pos("This list clears automatically", h58a) &&
   !occursin("These days are in the books", h58a) && !occursin("repeats in every report", h58a))
ok("the preheader is the count", startswith(preheader_of(h58a), "1 ledger waiting"))
ok("the text still has its own section and its three lines",
   occursin("20 August 2026 — saved, but its ledger cannot be made until", t58a) &&
   occursin("LEDGERS STILL WAITING", t58a) && occursin("repeats in every report until it is empty", t58a))

_, t58b, h58b = report([mkrow(W51, D51; day_diff = -1000.0, reason = "Short"), mkrow(W51, D51 - Day(3))])
ok("the pending section comes after every day card, and the footer after it",
   pos("7&nbsp;March 2035", h58b) < pos("Saved Days with Pending Ledgers", h58b) &&
   pos("4&nbsp;March 2035", h58b) < pos("Saved Days with Pending Ledgers", h58b) &&
   pos("Saved Days with Pending Ledgers", h58b) < pos("Powered by", h58b))
ok("the counts of all four kinds are in the preheader, uncapped, and nowhere else",
   (h4 = report([mkrow(W51, D51; day_diff = -1.0, reason = "x"),
                 mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true)])[3];
    startswith(preheader_of(h4), "1 day entered · 1 difference · 1 day changed · 1 ledger waiting") &&
    !occursin("1 ledger waiting</span>", h4)))

println("\n   The order of the page: days, the log warning, the pending ledgers, the footer")
_, _, hord = report([mkrow(W51, D51)]; problem = "Line 3 of Change Log.csv could not be read.",
                    note = "This replaces the report sent at 5:30 pm.", corrected = true)
ok("band, caption, notes, Days entered, change-log warning, Saved Days with Pending Ledgers, footer — in that order",
   (ps = [pos("class=\"lband\"", hord), pos("Includes everything saved up to", hord), pos("(This replaces", hord),
          pos(">Days entered</span>", hord), pos("THE CHANGE LOG COULD NOT BE READ PROPERLY,</strong>", hord),
          pos(">Saved Days with Pending Ledgers</span>", hord), pos("Powered by", hord)];
    issorted(ps) && all(<(typemax(Int)), ps)))
ok("the warning's words are the same, only its place changed",
   occursin("so this report may be missing entries. It is not a quiet day. Line 3 of Change Log.csv could not be read. Ask whoever looks after ldgr",
            html_plain(hord)))

println("\n   A day whose ledger is waiting is tagged in its card")
_, _, hpd = report([mkrow(W51, Date(2026, 8, 20))])
ok("an entered day waiting on a missing day: Ledger pending in place of Balanced, and (Awaiting Gap Day) after the date",
   !occursin(">Balanced</span>", hpd) && occursin(">Ledger pending</span>", hpd) &&
   occursin(r"20&nbsp;August 2026 <span[^>]*>\(Awaiting&nbsp;Gap&nbsp;Day\)</span>", hpd) &&
   count_of(">Ledger pending</span>", hpd) == 1)
ok("and the same day is in the pending section too", occursin("Saved, but its ledger cannot be made until 19", hpd))
_, _, hpd2 = report([mkrow(W51, Date(2026, 8, 20); day_diff = -1000.0, night_diff = 500.0, reason = "R", night_reason = "N")])
ok("with differences it also has the OB and CB tags, and Ledger pending is added after them",
   occursin(">OB Surplus \$500.00</span>", hpd2) && occursin(">CB Shortage (\$1,000.00)</span>", hpd2) &&
   pos(">CB Shortage (", hpd2) < pos(">Ledger pending</span>", hpd2))
_, _, hpd3 = report([mkrow(DateTime(2035, 3, 7, 9, 0), Date(2026, 8, 20)),
                     mkrow(DateTime(2035, 3, 7, 9, 30), Date(2026, 8, 20); what = "edited", pending = true,
                           changed = "Cash Sales \$500.00 -> \$700.00")])
ok("a pending-day edit is Ledger pending alone (not Numbers revised), with its table",
   !occursin(">Numbers revised</span>", hpd3) && occursin(">Ledger pending</span>", hpd3) &&
   occursin(">Cash Sales</td>", hpd3) && !occursin("Its ledger had not been made yet", hpd3))
ok("a waiting day that was not entered or changed in the report has no card, only the section",
   count_of(">Ledger pending</span>", h58a) == 0 && !occursin("Days entered", h58a))
plain58 = html_plain(h58a); f58 = text_facts(t58a)
ok("every date in the text is in the HTML", all(d -> date_shown(d, plain58), f58.dates) && !isempty(f58.dates))

# =============================================================================
# 59. The email, its key and the state file
# =============================================================================
println("\n59. html in the email, the key and the pending hand-over")

ee58 = Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T", "")
ok("an email with no HTML has no html key", !haskey(ee58, "html") &&
   !haskey(Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T", "2035-01-01T00:00:00.000Z"), "html"))
eh58 = Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T", "2035-01-01T00:00:00.000Z", "<p>H</p>")
ok("an email with HTML has it, and `_email` passes it through",
   eh58["html"] == "<p>H</p>" && haskey(eh58, "text") &&
   Notify._email(Notify.settings(), "S", "T"; html = "<p>H</p>")["html"] == "<p>H</p>" &&
   !haskey(Notify._email(Notify.settings(), "S", "T"), "html"))
old58 = join((ee58["from"], join(ee58["to"], ","), ee58["subject"], ee58["text"], get(ee58, "scheduled_at", "")), "|")
ok("an email with no HTML hashes exactly as it did before there was any",
   Notify._hash16(ee58) == bytes2hex(Notify.sha256(old58))[1:16])
ok("HTML changes the hash, and a change in the HTML changes it again",
   Notify._hash16(eh58) != Notify._hash16(Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T",
                                                             "2035-01-01T00:00:00.000Z")) &&
   Notify._hash16(eh58) != Notify._hash16(Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T",
                                                             "2035-01-01T00:00:00.000Z", "<p>I</p>")) &&
   Notify._hash16(eh58) == Notify._hash16(deepcopy(eh58)))
eu58 = Notify._email_dict("a@example.invalid", "b@example.invalid", "S", "T", "", "caf\xe9 <b>")
ok("HTML is valid UTF-8 whatever it was built from", isvalid(eu58["html"]) && eu58["html"] == "caf� <b>")

println("\n   Handed over, lost, asked about again")
fresh_schedule!(DateTime(2035, 5, 14, 17, 30))
logrow!(DateTime(2035, 5, 15, 10, 0), Date(2035, 5, 15); day_diff = -5.0, reason = FUNNY)
LOSE_REPLY[] = true
tick_at(DateTime(2035, 5, 15, 10, 0, 30))
orig58 = created()
ok("the email handed over has an HTML body, with the funny reason escaped",
   haskey(orig58.email, "html") && startswith(orig58.email["html"], "<!DOCTYPE html>") &&
   occursin(Notify._e(FUNNY), orig58.email["html"]) && occursin(FUNNY, body_of(orig58)))
pq58 = get(pending_of(state()), "email", Dict())
ok("the pending table keeps it exactly, through the state file",
   get(pq58, "html", "") == orig58.email["html"] && get(pq58, "text", "") == body_of(orig58))
rs58 = Notify._read_state()
ok("read back, the pending email is the one first sent, byte for byte",
   rs58 !== nothing && rs58.pending !== nothing && rs58.pending.email == orig58.email &&
   JSON3.write(rs58.pending.email) == JSON3.write(orig58.email))
ok("and its key still matches its content", keyhash(orig58.idem) == Notify._hash16(orig58.email))
logged!(DateTime(2035, 5, 15, 10, 3), Date(2035, 5, 14))
tick_at(DateTime(2035, 5, 15, 10, 6))
rep58 = length(CREATES) >= 2 ? CREATES[2] : NONE
ok("the repeat is the same JSON with the same key, though the books have moved on",
   rep58.idem == orig58.idem && JSON3.write(rep58.email) == JSON3.write(orig58.email))

println("\n   A hand-over written before the HTML existed")
fresh_schedule!(DateTime(2035, 5, 16, 17, 30))
logrow!(DateTime(2035, 5, 17, 10, 0), Date(2035, 5, 17); day_diff = -5.0, reason = "Old")
LOSE_REPLY[] = true
tick_at(DateTime(2035, 5, 17, 10, 0, 30))
new58 = created()
st58 = Notify._read_state()
old_email = Notify._email_dict(new58.email["from"], first(new58.email["to"]), new58.email["subject"],
                               new58.email["text"], new58.email["scheduled_at"])
old_key = "ldgr-203505171730-g" * string(st58.pending.generation) * "-" * Notify._hash16(old_email)
Notify._save_state(Notify._with_pending(st58, merge(st58.pending, (email = old_email, key = old_key))))
ok("the state file for it has no html line at all", !occursin("html", read(statefile(), String)))
ok("it reads back with no html key, and writes the same JSON as an email built without one",
   (r = Notify._read_state(); r.pending.email == old_email && !haskey(r.pending.email, "html") &&
    JSON3.write(r.pending.email) == JSON3.write(old_email)))
n58 = length(CREATES)
tick_at(DateTime(2035, 5, 17, 10, 6))
replay58 = length(CREATES) > n58 ? CREATES[n58 + 1] : NONE
ok("it is replayed as it was: no html, the same JSON, the same key",
   replay58.idem == old_key && !haskey(replay58.email, "html") &&
   JSON3.write(replay58.email) == JSON3.write(old_email))

println("\n   Through Resend.jl, to a stub on this machine")
STUB3_PORT = spare_port()
STUB3 = Logging.with_logger(Logging.NullLogger()) do
    HTTP.serve!(stub_handler, "127.0.0.1", STUB3_PORT)
end
Resend.API_BASE[] = "http://127.0.0.1:$(STUB3_PORT)"
local_only()
fresh_schedule!(DateTime(2035, 5, 18, 17, 30))         # (this puts the fake mailer back, so it comes first)
Notify.MAILER[] = (send   = (key, email, idem) -> Resend.send(key, email; idempotency_key = idem),
                   cancel = Resend.cancel)
STUB_MODE[] = :auto
empty!(STUB_HITS)
logrow!(DateTime(2035, 5, 19, 10, 0), Date(2035, 5, 19); day_diff = -5.0, reason = FUNNY)
res = tick_at(DateTime(2035, 5, 19, 10, 0, 30))
hit58 = isempty(STUB_HITS) ? (body = "{}",) : STUB_HITS[1]
jb58 = try JSON3.read(hit58.body) catch; nothing end
ok("the JSON the stub received carries the html beside the text",
   res == [:scheduled] && jb58 !== nothing && haskey(jb58, :html) && startswith(String(jb58.html), "<!DOCTYPE html>") &&
   endswith(strip(String(jb58.html)), "</html>") && occursin(FUNNY, String(jb58.text)) &&
   occursin(Notify._e(FUNNY), String(jb58.html)))
rr58 = Changes.rows_checked(DateTime(2035, 5, 18, 17, 30), DateTime(2035, 5, 19, 17, 30))
ok("and they are the subject, text and HTML of the report for that stretch, word for word",
   (Notify._report(rr58[1], rr58[2], DateTime(2035, 5, 18, 17, 30), DateTime(2035, 5, 19, 17, 30)) ==
    (String(jb58.subject), String(jb58.text), String(jb58.html))))
Notify.MAILER[] = FAKE
Resend.API_BASE[] = STUB2_BASE
HTTP.forceclose(STUB3)
local_only()

println("\n   If the HTML could not be built the report still goes, as text")
child58 = in_child("""
    Core.eval(Notify, :(function _html_body(plan, rows::Vector{Changes.Row}, problem::AbstractString,
                                            from::Union{Nothing,DateTime}, to::DateTime;
                                            note::AbstractString = "", corrected::Bool = false,
                                            subject::AbstractString = "")
        error("test: the layout broke")
    end))
    rows = Changes.Row[]
    a, b, c = Notify._report(rows, "", nothing, DateTime(2035, 1, 2))
    println("RESULT html=", repr(c))
    println("RESULT same=", (a, b) == Notify._digest(rows, "", nothing, DateTime(2035, 1, 2)))
    e = Notify._email(Notify.settings() === nothing ? (from = "f", to = "t") : Notify.settings(), a, b; html = c)
    println("RESULT nohtml=", !haskey(e, "html"))
    """, "")
ok("the child ran ($(child58[1]))", child58[1] == 0)
ok("an HTML body that fails is empty, the text is unharmed, and the email has no html key",
   child_result(child58[2], "html") == "\"\"" && child_result(child58[2], "same") == "true" &&
   child_result(child58[2], "nohtml") == "true")

write(LOGP, SNAP51)
rm(statefile(); force = true)
ok("(the change log is put back)", logsnap() == SNAP51)

# =============================================================================
# 60. The key, once more, after the HTML groups
# =============================================================================
println("\n60. The API key, after the HTML groups")

ok("THE API KEY IS NOWHERE IN THE AUDIT LOG", !occursin(KEY, auditlog()))
written59 = String[]
for (dir, _, fs) in walkdir(SCRATCH), f in fs
    local fp = joinpath(dir, f)
    fp == CONFIG && continue
    push!(written59, fp)
end
leaks59 = filter(p -> occursin(KEY, read(p, String)), written59)
ok("nor in any file this run wrote ($(length(written59)) files)", isempty(leaks59) || (println("      -> $leaks59"); false))
ok("nor in any email or HTML body handed over ($(length(ALL_CREATES)))",
   all(c -> !occursin(KEY, JSON3.write(c.email)) && !occursin(KEY, get(c.email, "html", "")) && !occursin(KEY, c.idem),
       ALL_CREATES))
ok("and an HTML body was handed over in most of them", count(c -> haskey(c.email, "html"), ALL_CREATES) > length(ALL_CREATES) ÷ 2)


# =============================================================================
# 61. Review fixes to the HTML body
# =============================================================================
println("\n61. Semicolons and line breaks in reasons, the fallback, the preheader, the nesting")

println("\n   A reason that contains \"; \"")
SEMI = "Paid the courier; receipt in folder"
_, tsem, hsem = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                              changed = "Reason \"$(SEMI)\" -> \"ok\"; Taxi Fare \$1.00 -> \$2.00; " *
                                        "Night reason \"a; b\" -> \"c; d\"")])
ok("the edit's explanation is one stacked row, before struck and after in bold",
   occursin("<s>$(SEMI)</s>", hsem) && occursin("<strong>ok</strong>", hsem))
ok("the figure after it is still a figure row", occursin("<s>\$1.00</s>", hsem) && occursin(">\$2.00</td>", hsem))
ok("and a second explanation with a semicolon on both sides is one row too",
   occursin("<s>a; b</s>", hsem) && occursin("<strong>c; d</strong>", hsem) && occursin(">OB explanation</div>", hsem))
ok("nothing is left as a broken verbatim row", count_of("word-wrap:break-word;\">receipt in folder", hsem) == 0 &&
   !occursin(">receipt in folder\" ", hsem))
ok("the text body is unchanged: it still splits at the semicolon",
   occursin("      Reason \"Paid the courier\n      receipt in folder\" -> \"ok\"\n", tsem))
_, _, hsem1 = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                            changed = "Reason \"$(SEMI)\" -> \"\"; Taxi Fare \$1.00 -> \$2.00")])
ok("a cleared explanation has no row, and the part after it is still a figure row",
   !occursin("receipt in folder", hsem1) && occursin("<s>\$1.00</s>", hsem1))
_, _, hsem2 = report([mkrow(W51, D51; day_diff = -5.0, reason = SEMI)])
ok("a semicolon in an explanation that was not edited shows whole, on the bullet",
   occursin("with explanation: $(SEMI)</td>", hsem2))
ok("a label the log can emit starts a new part; a continuation that only looks like one does not",
   (hp = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                       changed = "Reason \"x; Kind of day\" -> \"y\"; Cash Sales \$1.00 -> \$2.00")])[3];
    occursin("<s>x; Kind of day</s>", hp) && occursin("<s>\$1.00</s>", hp) && !occursin(">Day type<", hp)))

println("\n   Line breaks in a reason")
_, _, hnl = report([mkrow(W51, D51; day_diff = -5.0, reason = "line one\nline two\r\nline <three>"),
                    mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                          changed = "Reason \"a\nb\" -> \"c\r\nd\"")])
ok("each break in an explanation is a <br>, after escaping",
   occursin("line one<br>line two<br>line &lt;three&gt;", hnl))
ok("and in the stacked rows, before and after", occursin("<s>a<br>b</s>", hnl) && occursin("<strong>c<br>d</strong>", hnl))
ok("no raw newline sits inside a reason", !occursin("line one\nline two", hnl))

println("\n   The warning and the released ledgers")
ok("a 16 px gap precedes the problem warning, which follows the day cards",
   occursin("</td></tr>\n<tr><td height=\"16\"", h52e) &&
   pos("<tr><td height=\"16\"", h52e) < pos("THE CHANGE LOG COULD NOT BE READ PROPERLY,</strong>", h52e) &&
   pos(">Days entered</span>", h52e) < pos("<tr><td height=\"16\"", h52e))
hrel = report(CORPUS51[9][3])[3]
ok("a released ledger is a Ledger made line in the gap day's card, its tags and explanations under it",
   occursin(r"<div class=\"la\"[^\n]*&#10003; Ledger made for 5&nbsp;March 2035</div>\n<div[^\n]*>(<span[^>]*>[^<]*</span> ?)+</div>\n<div class=\"ls\"[^\n]*>OB explanation: ", hrel))
ok("one Ledger made line per released day", count_of("&#10003; Ledger made for", hrel) == 1)
hrel2 = report([mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 5); what = "edited"),
                mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 4); what = "released", by = Date(2035, 3, 5)),
                mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 6); what = "released", by = Date(2035, 3, 5))])[3]
ok("an earlier day whose save released two ledgers has a line for each, in date order",
   count_of("&#10003; Ledger made for", hrel2) == 2 && pos("Ledger made for 4&nbsp;March", hrel2) < pos("Ledger made for 6&nbsp;March", hrel2))
ok("a released ledger and no edit: the day gets a card with its Changed on bullet",
   occursin("Changed on 07-03-2035 by tester at 09:00", hrel2))

println("\n   The preheader also draws on days changed that still have a difference")
_, _, hpc = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                          day_diff = -50.0, reason = "Still short")])
ok("a changed day that still has a difference is in it",
   occursin("CB Shortage (\$50.00) on 2&nbsp;March.", preheader_of(hpc)))
_, _, hpc2 = report([mkrow(W51, D51; day_diff = -1000.0, reason = "a"), mkrow(W51 - Day(1), D51 - Day(1); day_diff = 7.0, reason = "b"),
                     mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                           day_diff = -50.0, reason = "c")])
ok("the newest days come first and the list stops at two",
   occursin("CB Shortage (\$1,000.00) on 7&nbsp;March. CB Surplus \$7.00 on 6&nbsp;March.", preheader_of(hpc2)) &&
   !occursin("\$50.00", preheader_of(hpc2)))

println("\n   The fallback, and what it says")
child61 = in_child("""
    using Logging
    row = Changes.Row((DateTime(2035, 3, 7, 9, 0), "t", "saved", Date(2035, 3, 7), "trading", "added", "written",
                       0.0, 0.0, "", "", NaN, NaN, "", false, false, false, false, nothing))
    io = IOBuffer()
    Core.eval(Notify, :(function _html_body(plan, rows::Vector{Changes.Row}, problem::AbstractString,
                                            from::Union{Nothing,DateTime}, to::DateTime;
                                            note::AbstractString = "", corrected::Bool = false,
                                            subject::AbstractString = "")
        error("test: broke on re_ABCDEFGH12345 for the second time")
    end))
    a = b = nothing
    Logging.with_logger(Logging.SimpleLogger(io, Logging.Warn)) do
        Notify._report([row], "", nothing, DateTime(2035, 3, 8))
        Notify._report([row], "", nothing, DateTime(2035, 3, 8))
    end
    w = String(take!(io))
    println("RESULT warned=", count("could not be built", w))
    println("RESULT scrubbed=", !occursin("re_ABCDEFGH12345", w) && occursin("********", w))
    println("RESULT audit=", isfile(Layout.audit_log_path()))
    Core.eval(Notify, :(function _html_body(plan, rows::Vector{Changes.Row}, problem::AbstractString,
                                            from::Union{Nothing,DateTime}, to::DateTime;
                                            note::AbstractString = "", corrected::Bool = false,
                                            subject::AbstractString = "")
        throw(InterruptException())
    end))
    got = try
        Notify._report([row], "", nothing, DateTime(2035, 3, 8)); "returned"
    catch e
        e isa InterruptException ? "interrupted" : "other"
    end
    println("RESULT interrupt=", got)
    """, "")
ok("the child ran ($(child61[1]))", child61[1] == 0)
ok("a failing layout warns once for two builds, with the key-shaped text masked, and writes no audit log",
   child_result(child61[2], "warned") == "1" && child_result(child61[2], "scrubbed") == "true" &&
   child_result(child61[2], "audit") == "false")
ok("an interrupt is not swallowed", child_result(child61[2], "interrupt") == "interrupted")

println("\n   Live reads are shared by the two renderings")
reads61 = Ref(0)
ok("the day before is read once per day for the text and the HTML together",
   let cnt = Ref(0)
       task_local_storage(:ldgr_live_reads, Dict{Any,Any}()) do
           for _ in 1:3
               Notify._live((:prior, Date(2035, 1, 1)), () -> (cnt[] += 1; nothing))
           end
       end
       cnt[] == 1 && Notify._live((:prior, Date(2035, 1, 1)), () -> 42) == 42
   end)
ok("and it is read fresh when no report is being built", let cnt = Ref(0)
       Notify._live(:k, () -> cnt[] += 1); Notify._live(:k, () -> cnt[] += 1); cnt[] == 2
   end)

# =============================================================================
println("\n62. The kind of day is worded for people, in the log and in old rows")
# =============================================================================

a62 = blank_amounts(); a62[:opening_balance] = 1000.0; a62[:closing_balance] = 1000.0
work62 = DayRecord(Date(2035, 3, 2), a62, STATUS_TRADING, "", "")
off62  = closed_day(Date(2035, 3, 2), 1000.0)
ok("the writer words a Work day made an Off day as Work day -> Off day",
   occursin("Kind of day Work day -> Off day", Changes._changed_text(work62, off62)) &&
   !occursin("trading", Changes._changed_text(work62, off62)) &&
   !occursin("closed", Changes._changed_text(work62, off62)))
ok("and an Off day made a Work day the other way round",
   Changes._changed_text(off62, work62) == "Kind of day Off day -> Work day")
ok("kind_words leaves anything else as it is",
   Changes.kind_words("trading") == "Work day" && Changes.kind_words("closed") == "Off day" &&
   Changes.kind_words("shop") == "shop")

legacy62 = mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                 changed = "Cash Sales \$500.00 -> \$700.00; Kind of day trading -> closed")
modern62 = mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                 changed = "Cash Sales \$500.00 -> \$700.00; Kind of day Work day -> Off day")
s62l, t62l, h62l = report([legacy62])
_, t62m, h62m = report([modern62])
ok("a legacy row prints the new words in the text, and never the stored ones",
   occursin("Kind of day Work day -> Off day", t62l) && !occursin("Kind of day trading", t62l))
ok("a legacy row and a new one print the same text and the same HTML", t62l == t62m && h62l == h62m)
ok("a legacy row shows Work day and Off day in the HTML",
   occursin("<s>Work day</s>", h62l) && occursin(">Off day</td>", h62l) && !occursin(">closed<", h62l) &&
   !occursin(">trading<", h62l))
_, t62c, _ = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                          changed = "Kind of day closed -> trading")])
ok("a legacy closed -> trading part reads Off day -> Work day",
   occursin("Kind of day Off day -> Work day", t62c))
_, t62u, _ = report([mkrow(DateTime(2035, 3, 7, 10, 5), Date(2035, 3, 2); what = "edited", cross = true,
                          changed = "Kind of day trading -> shop")])
ok("a part that is not one of the two stored words is left verbatim",
   occursin("Kind of day trading -> shop", t62u))

# =============================================================================
println("\n63. The title band, the caption, the bullets, 24-hour times, the footer")
# =============================================================================

ok("_times24 converts ldgr's own 12-hour times, including noon and midnight",
   Notify._times24("at 5:30 pm, 9:05 am, 12:00 pm and 12:15 am") == "at 17:30, 09:05, 12:00 and 00:15")
ok("_times24 leaves everything else alone", Notify._times24("between 5:30 and 6, 13:00, 5:75 pm") == "between 5:30 and 6, 13:00, 5:75 pm")
ok("_clock24 pads the hour", Notify._clock24(DateTime(2035, 3, 7, 9, 5)) == "09:05" &&
                             Notify._clock24(DateTime(2035, 3, 7, 17, 30)) == "17:30")

_, _, h63 = report([mkrow(DateTime(2035, 3, 7, 9, 5), D51; who = "reception")]; note = "Sent late, at 5:42 pm.")
p63 = html_plain(h63)
println("\n   The title band")
ok("the band reads LDGR | Daily Report | dd-mm-yyyy; no (Urgent Care) anywhere",
   occursin("LDGR | Daily Report | 07-03-2035", p63) && !occursin("Urgent Care", h63))
ok("it is one full-width cell with the green fill set twice and the cards' rounded corners",
   count_of("class=\"lband\" bgcolor=\"#1F6F5C\" style=\"background-color:#1F6F5C;border-radius:12px;", h63) == 1)
ok("white text on it: every piece carries color #FFFFFF, LDGR bold and the rest semibold",
   occursin("<span style=\"color:#FFFFFF;font-weight:700;\">LDGR</span>", h63) &&
   occursin("<span style=\"color:#FFFFFF;font-weight:600;\">Daily Report</span>", h63) &&
   occursin("<span style=\"color:#FFFFFF;font-weight:600;\">07-03-2035</span>", h63))
ok("the separators are a pale green with no rgba, anywhere in the page",
   count_of("<span style=\"color:#B9D9CE;\"> | </span>", h63) == 2 && !occursin("rgba", h63))
ok("the text is one row: nowrap, inside one div in one cell",
   occursin("<div class=\"lh\" style=\"font-size:18.5px;line-height:1.3;white-space:nowrap;color:#FFFFFF;\">", h63))
ok("the band is the first visible thing: before the caption, the heading and the days",
   pos("class=\"lband\"", h63) < pos("Includes everything", h63) && pos("class=\"lband\"", h63) < pos(">Days entered</span>", h63))
ok("a corrected report says Corrected Report, on its own (longer) class, and smaller",
   (hcb = report([mkrow(W51, D51)]; corrected = true)[3];
    occursin("LDGR | Corrected Report | 07-03-2035", html_plain(hcb)) &&
    occursin("<div class=\"lhc\" style=\"font-size:16px;line-height:1.3;white-space:nowrap;color:#FFFFFF;\">", hcb)))
ok("the date is the report's own, with single dashes, whatever the day entered",
   occursin("LDGR | Daily Report | 01-12-2035",
            html_plain(report([mkrow(W51, D51)]; to = DateTime(2035, 12, 1, 17, 30))[3])))
ok("the size is as large as fits at 360px inline and steps up at 375/390/412/430/600 for both wordings",
   all(w -> occursin("@media screen and (min-width:$(w)px){.lh{font-size:", h63), (375, 390, 412, 430, 600)) &&
   occursin("@media screen and (min-width:375px){.lh{font-size:19.5px!important}.lhc{font-size:17px!important}}", h63) &&
   occursin("@media screen and (min-width:390px){.lh{font-size:20.5px!important}.lhc{font-size:17.5px!important}}", h63) &&
   occursin("@media screen and (min-width:412px){.lh{font-size:21.5px!important}.lhc{font-size:19px!important}}", h63) &&
   occursin("@media screen and (min-width:430px){.lh{font-size:23px!important}.lhc{font-size:20px!important}}", h63) &&
   occursin("@media screen and (min-width:600px){.lh{font-size:28px!important}.lhc{font-size:28px!important}}", h63))
ok("one rule steps the size down under 360px",
   occursin("@media screen and (max-width:359px){.lh{font-size:16px!important}.lhc{font-size:14px!important}}", h63))
ok("no size is over the 28px cap",
   all(m -> parse(Float64, m[1]) <= 28, eachmatch(r"\.lhc?\{font-size:([0-9.]+)px", h63)) &&
   all(m -> parse(Float64, m[1]) <= 28, eachmatch(r"class=\"lhc?\" style=\"font-size:([0-9.]+)px", h63)))
ok("in dark mode the band stays green, with the text white (its pieces have no dark rule of their own)",
   occursin(".lband{background-color:#175649!important}", h63) && !occursin(".lh{color", h63))
ok("no Covering line, no summary card", !occursin("Covering", h63) && !occursin("covering", p63) && !occursin("1 day entered", unseen(h63)))

println("\n   Caption, notes, bullets")
ok("the caption and the notes are on the 24-hour clock",
   occursin("Includes everything saved up to 09:05 on 7 March.", p63) && occursin("(Sent late, at 17:42.)", p63) &&
   occursin("09:05 &ndash; entered and saved by reception", h63))
ok("no am or pm time is left anywhere in a report of ldgr's own words",
   all(c -> !occursin(r"\b\d{1,2}:\d{2}\s?(am|pm)\b", html_plain(report(c[3]; c[2]...)[3])), CORPUS51))
ok("the Days entered heading is 14px in the brand green",
   occursin("<span class=\"la\" style=\"font-size:14px;line-height:18px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:#1F6F5C;\">Days entered</span>", h63))

_, t63e, h63e = report([mkrow(DateTime(2035, 3, 7, 15, 40), D51; who = "reception"),
                        mkrow(DateTime(2035, 3, 7, 16, 35), D51; what = "edited", who = "manager")])
ok("a day's events are bullets in time order, the last same-session update shown",
   pos("15:40 &ndash; entered and saved by reception", h63e) < pos("16:35 &ndash; updated by manager", h63e) &&
   occursin("&bull;</td>", h63e) && !occursin("Entered by", h63e) && !occursin("Changed again", h63e) &&
   !occursin("<ul", h63e) && occursin("Changed again by manager at 4:35 pm.", t63e))
ok("a same-session update is not reported: no Numbers revised tag, no table, no caption",
   occursin(">Balanced</span>", h63e) && !occursin(">Numbers revised</span>", h63e) && !occursin(">Before</td>", h63e))
_, _, h63a = report([mkrow(DateTime(2035, 3, 7, 15, 40), D51; who = "reception", day_diff = -1000.0, reason = "Short"),
                     mkrow(DateTime(2035, 3, 7, 16, 35), D51; what = "edited", who = "manager", day_diff = -1000.0, reason = "Short")])
ok("the same on a day with a difference: its explanation is on the entry bullet",
   pos("15:40 &ndash; entered and saved by reception with explanation: Short", h63a) < pos("16:35 &ndash; updated by manager", h63a) &&
   occursin(">CB Shortage (\$1,000.00)</span>", h63a))
_, _, h63g = report([mkrow(DateTime(2035, 3, 7, 9, 0), Date(2035, 3, 4); who = "manager", gap = true)])
ok("and on a gap day",
   occursin("09:00 &ndash; entered and saved by manager", h63g) && !occursin("Entered by", h63g))

_, _, h63t = report([mkrow(DateTime(2035, 3, 7, 16, 0), D51; who = "5:30 pm desk", day_diff = -1000.0,
                           reason = "Paid the courier at 5:30 pm")];
                    problem = "Line 3 said 5:30 pm and could not be read.")
ok("typed text is never converted: an explanation, a name, and the change log's problem",
   occursin("Paid the courier at 5:30 pm", h63t) && occursin("entered and saved by 5:30 pm desk", h63t) &&
   occursin("Line 3 said 5:30&nbsp;pm and could not be read.", h63t))

println("\n   The footer")
ok("the footer is the credit, centred, in soft ink, and the Records folder is not in the HTML",
   occursin("Powered by <b style=\"font-weight:600;\">SolRegia</b></div>", h63) &&
   occursin("font-size:12px;line-height:18px;color:#5B6660;text-align:center;", h63) &&
   !occursin("Records folder:", h63) && !occursin("This report is sent at", h63) &&
   !occursin("<svg", h63) && occursin("Records folder: ", report([mkrow(W51, D51)])[2]))

# =============================================================================
println("\n64. The second round (handoff/email-html-round2.md): revised days, first saves, the next morning")
# =============================================================================

"A saved row in the real change log, for the 'First saved on' bullet of a day the report calls revised."
function first_save!(when::DateTime, d::Date; kw...)
    logrow!(when, d; kw...)
end
D64 = Date(2036, 4, 2)
first_save!(DateTime(2036, 4, 2, 16, 50), D64; who = "reception", day_diff = -2000.0, reason = "Paid the courier")
ok("(a first save of 2 April 2036 is in the log, at 16:50)", Changes.first_saved_at(D64) == DateTime(2036, 4, 2, 16, 50))

println("\n   A revised day that was not entered in this report")
edit64 = mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true, balances = true,
               was_day = -2000.0, day_diff = 0.0,
               changed = "Closing Balance \$18,000.00 -> \$20,000.00; Reason \"Paid the courier\" -> \"\"")
_, t64, h64 = report([edit64]; from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))
ok("it opens with 'First saved on <date> at <time>' and the explanation it had then, taken from the cleared explanation",
   occursin("First saved on 02-04-2036 at 16:50 with explanation: Paid the courier</td>", h64))
ok("then one bullet per reported edit", occursin("Changed on 03-04-2036 by manager at 10:05</td>", h64) &&
   pos("First saved on", h64) < pos("Changed on 03-04-2036", h64))
ok("the cleared explanation is not a table row, so the old words appear once, on the first-save bullet",
   count_of("Paid the courier", h64) == 1 && !occursin(">Explanation<", h64))
ok("it is Balanced with (Previously Not Balanced), and its table shows the figure and CB Shortage (\$2,000.00) -> \$0.00",
   occursin(">Balanced</span>", h64) && occursin("(Previously&nbsp;Not&nbsp;Balanced)", h64) &&
   occursin(r">CB Shortage</td><td[^>]*><s>\(\$2,000\.00\)</s></td><td[^>]*>\$0\.00</td>", h64))
ok("the text still says it did not balance before, and balances now",
   occursin("It did not balance before: shortage of \$2,000.00 during the day.", t64) && occursin("It balances now.", t64))

_, _, h64b = report([mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true,
                           day_diff = -2000.0, was_day = -2000.0, reason = "Paid the courier, again",
                           changed = "Reason \"Paid the courier\" -> \"Paid the courier, again\"")];
                    from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))
ok("an explanation that changed is shown before and after, and the first-save sentence carries the BEFORE side",
   occursin("First saved on 02-04-2036 at 16:50 with explanation: Paid the courier</td>", h64b) &&
   occursin("<s>Paid the courier</s>", h64b) && occursin("<strong>Paid the courier, again</strong>", h64b) &&
   occursin(">Numbers revised</span>", h64b))
ok("with an edit that left the explanation alone the first-save sentence carries the explanation the row holds",
   occursin("First saved on 02-04-2036 at 16:50 with explanation: Paid the courier</td>",
            report([mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true,
                          day_diff = -2000.0, was_day = -2000.0, reason = "Paid the courier",
                          changed = "Cash Sales \$1.00 -> \$2.00")];
                   from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))[3]))
ok("a balanced day has no explanation after its first-save time",
   (hb = report([mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true, was_day = 0.0,
                       changed = "Cash Sales \$1.00 -> \$2.00")];
                from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))[3];
    occursin("First saved on 02-04-2036 at 16:50</td>", hb) && !occursin("with explanation", hb)))
ok("both differences before the edit: with explanations: OB – …; CB – …",
   occursin("with explanations: OB &ndash; Float moved; CB &ndash; Paid the courier</td>",
            report([mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true,
                          day_diff = -2000.0, night_diff = 500.0, was_day = -2000.0, was_night = 500.0,
                          reason = "Paid the courier", night_reason = "Float moved", changed = "Cash Sales \$1.00 -> \$2.00")];
                   from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))[3]))
ok("a difference with no explanation before the edit: no explanation given",
   occursin("First saved on 02-04-2036 at 16:50, no explanation given</td>",
            report([mkrow(DateTime(2036, 4, 3, 10, 5), D64; what = "edited", who = "manager", cross = true,
                          day_diff = -2000.0, was_day = -2000.0, reason = "", changed = "Cash Sales \$1.00 -> \$2.00")];
                   from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))[3]))
ok("with no first save in the log the bullet is left out rather than guessed",
   !occursin("First saved on", report([mkrow(DateTime(2036, 5, 3, 10, 5), Date(2036, 5, 2); what = "edited", cross = true,
                                             changed = "Cash Sales \$1.00 -> \$2.00")])[3]))

println("\n   A day entered in this report and edited after its session (the next morning)")
_, t64n, h64n = report([mkrow(DateTime(2035, 3, 6, 18, 10), D51 - Day(1); who = "reception"),
                        mkrow(DateTime(2035, 3, 7, 9, 20), D51 - Day(1); what = "edited", who = "manager", cross = true,
                              changed = "Cash Sales \$16,000.00 -> \$17,000.00; Closing Balance \$20,000.00 -> \$21,000.00")])
ok("the entry bullet, then the change bullet, in one card",
   occursin("18:10 &ndash; entered and saved by reception</td>", h64n) && occursin("Changed on 07-03-2035 by manager at 09:20</td>", h64n) &&
   pos("18:10 &ndash;", h64n) < pos("Changed on 07-03-2035", h64n) && count_of(">Days entered</span>", h64n) == 1)
ok("it is Numbers revised, and its table shows the figures", occursin(">Numbers revised</span>", h64n) &&
   occursin(">Cash Sales</td>", h64n) && occursin("<s>\$16,000.00</s>", h64n) && !occursin("Previous Gap Day", h64n))
ok("the text calls it a day entered with a spelled-out change",
   occursin("Entered by reception at 6:10 pm.", t64n) && occursin("Changed on 7 March 2035 by manager at 9:20 am:", t64n))

println("\n   Precedence of the tags")
_, _, hp1 = report([mkrow(DateTime(2035, 3, 7, 10, 5), D51 - Day(5); what = "edited", cross = true, day_diff = -50.0, reason = "r",
                          was_day = -50.0, changed = "Cash Sales \$1.00 -> \$2.00; Kind of day Work day -> Off day")])
ok("a kind change overrides everything: Work status update only, though the day still has a shortage",
   occursin(">Work status update</span>", hp1) && !occursin(">Numbers revised</span>", hp1) && !occursin(">CB Shortage (", hp1) &&
   !occursin(">Balanced</span>", hp1))
_, _, hp2 = report([mkrow(DateTime(2035, 3, 7, 10, 5), D51 - Day(5); what = "edited", cross = true, balances = true, was_day = -50.0,
                          changed = "Cash Sales \$1.00 -> \$2.00")])
ok("a reported edit decides between Balanced (it cleared a difference) and Numbers revised, over the day's own state",
   occursin(">Balanced</span>", hp2) && !occursin(">Numbers revised</span>", hp2))
_, _, hp3 = report([mkrow(DateTime(2035, 3, 7, 10, 5), D51 - Day(5); what = "edited", cross = true, day_diff = -50.0, was_day = 0.0,
                          reason = "r", changed = "Cash Sales \$1.00 -> \$2.00")])
ok("revised and still or newly unbalanced is Numbers revised only, with no CB tag",
   occursin(">Numbers revised</span>", hp3) && !occursin(">CB Shortage (", hp3))
ok("a same-session edit does not count: the day's own tags show",
   (hp4 = report([mkrow(DateTime(2035, 3, 7, 15, 0), D51; day_diff = -50.0, reason = "r"),
                  mkrow(DateTime(2035, 3, 7, 15, 30), D51; what = "edited", day_diff = -50.0, reason = "r")])[3];
    occursin(">CB Shortage (\$50.00)</span>", hp4) && !occursin(">Numbers revised</span>", hp4)))
ok("an Off day edited in the same session is still just Off day",
   occursin(">Off day</span>", report([mkrow(DateTime(2035, 3, 7, 15, 0), D51; kind = "closed"),
                                       mkrow(DateTime(2035, 3, 7, 15, 30), D51; what = "edited", kind = "closed")])[3]))

println("\n   The shape of a card")
_, _, hc64 = report([edit64]; from = DateTime(2036, 4, 2, 17, 30), to = DateTime(2036, 4, 3, 17, 30))
cardcells = collect(eachmatch(r"<tr><td valign=\"top\" style=\"padding:0 8px 0 0;\">(.*?)</td><td valign=\"top\" align=\"right\" style=\"padding:0;white-space:nowrap;\">(.*?)</td></tr>"s, hc64))
ok("a card is a two-column table: the left column holds the date and bullets, the right ONLY the tags",
   length(cardcells) == 1 && occursin("2&nbsp;April 2036", cardcells[1][1]) && occursin("First saved on", cardcells[1][1]) &&
   !occursin("<span class=\"la lb\"", cardcells[1][1]) && occursin("<span class=\"la lb\"", cardcells[1][2]) &&
   !occursin("First saved", cardcells[1][2]) && !occursin("explanation", lowercase(cardcells[1][2])) &&
   all(m -> occursin("white-space:nowrap", m.match), eachmatch(r"<div style=\"margin-top:[0-9]+px;text-align:right;[^>]*>", cardcells[1][2])))
ok("the change table is a full-width row (colspan 2) under the two columns, inside the same card",
   occursin("</td></tr>\n<tr><td colspan=\"2\" style=\"padding:0;\">\n<table", hc64) &&
   pos("colspan=\"2\" style=\"padding:0;\"", hc64) < pos("Powered by", hc64))
ok("the date is 15px semibold ink", occursin("<div class=\"li\" style=\"font-size:15px;line-height:22px;font-weight:600;color:#1C2521;\">2&nbsp;April 2036 <span", hc64))
ok("cards are separated by the 12px spacer, so several never run together",
   count_of("<tr><td height=\"12\"", report([mkrow(W51, D51), mkrow(W51, D51 - Day(1)), mkrow(W51, D51 - Day(2))])[3]) == 2)
ok("none of the removed furniture: no Work day label, no captions, no separator line inside a card, no stripe",
   (hall = report(CORPUS51[4][3])[3]; !occursin(">Work day<", hall) && !occursin("During the day", hall) &&
    !occursin("Opening balance", hall) && !occursin("border-left:4px", replace(hall, r"<td class=\"ldb lsd\"[^>]*>" => ""))))
ok("two tags stacked: the opening above the closing, each in its own right-aligned block",
   (hs2 = report(CORPUS51[4][3])[3]; pos(">OB Shortage", hs2) < pos(">CB Shortage", hs2) &&
    count_of("text-align:right;white-space:nowrap;\"><span", hs2) == 2))

# put the change log back as group 59 left it
write(LOGP, SNAP51)
ok("(the change log is put back)", logsnap() == SNAP51)

println("\n", repeat("=", 74))
println("  PASSED $(PASS[])   FAILED $(FAIL[])")
println(repeat("=", 74))
