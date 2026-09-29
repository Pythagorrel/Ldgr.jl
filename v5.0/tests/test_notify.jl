# =============================================================================
# test_notify.jl — the paper trail and the one daily report.
#
# Run:  LEDGER_ROOT=/tmp/ldgr_notify julia --startup-file=no test_notify.jl
#
# Writes to LEDGER_ROOT only, and CLEARS IT FIRST so the run is repeatable.
# It refuses to start if LEDGER_ROOT is unset or names a folder called
# "Records". Never point this at the real books.
#
# NOTHING IS EVER SENT. `Notify.TRANSPORT[]` is replaced with a function that
# collects what it was handed, which is the only reason the send path can be
# tested at all — the alternative needs a mailbox, an internet connection and
# somebody's password. The settings file is written INSIDE the scratch root and
# pointed at with LDGR_NOTIFY_CONFIG before anything is loaded, so an installed
# notify.toml is never read and never touched, and LDGR_NO_DIGEST=1 keeps the
# scheduler from ever starting.
#
# WHAT MATTERS HERE IS THE POLICY, not the plumbing. Two things are being
# proved. First, that every write to the books leaves a row behind — whether or
# not email is configured — so nothing that happens to a day can be quietly
# undone. Second, that the one report the owner receives says, in plain words
# and without a single warning code, what was entered, what was changed after
# the fact, which gaps were filled and which ledgers are still waiting.
# =============================================================================

using Dates

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

# The mailbox settings live inside the scratch root, so the installed
# notify.toml (if the clinic ever writes one) is never read by a test.
const CONFIG = joinpath(SCRATCH, "notify-test.toml")
ENV["LDGR_NOTIFY_CONFIG"] = CONFIG          # absent until it is written, below
ENV["LDGR_NO_DIGEST"]     = "1"             # no timer, ever, from a test

include("main.jl")

basename(rstrip(Layout.ROOT, ['\\', '/'])) == "Records" &&
    error("Layout.ROOT resolved to a Records folder. Refusing to run.")

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
    Changes.after_save(out; rec = rec, previous = previous, before = before)
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

digest(from = nothing, to = now()) = Notify.build_digest(from, to)

# A day that was both entered and changed inside one window is told once, as a
# day entered, with its final figures — that is the point of the same-date rule.
# To read the CHANGES section a window has to start AFTER the day went in, which
# is what these two give: "since midnight" for a day saved yesterday, and "the
# last hour" for a day saved earlier today.
since_midnight() = DateTime(Dates.today())
since_an_hour_ago() = now() - Hour(1)

# --- the outbox -------------------------------------------------------------
outbox() = isdir(Layout.outbox_dir()) ?
    sort(filter(f -> endswith(f, ".txt"), readdir(Layout.outbox_dir()))) : String[]
sentbox() = isdir(Layout.sent_dir()) ?
    sort(filter(f -> endswith(f, ".txt"), readdir(Layout.sent_dir()))) : String[]
auditlog() = isfile(Layout.audit_log_path()) ? read(Layout.audit_log_path(), String) : ""

const SENT = Vector{NTuple{3,String}}()
capture(to, subject, body) = (push!(SENT, (String(to), String(subject), String(body))); nothing)

const PASSWORD = "sw0rdf1sh-app-password"
const WHO = get(ENV, "USERNAME", get(ENV, "USER", ""))

println("\n", repeat("=", 74))
println("  LDGR v4.0 — THE CHANGE LOG AND THE ONE DAILY REPORT")
println("  ROOT: $(Layout.ROOT)")
println(repeat("=", 74))

# =============================================================================
# 1. Off by default
# =============================================================================
println("\n1. With no notify.toml at all")

ok("email is off", Notify.enabled() === false)
ok("and there are no settings to read", Notify.settings() === nothing)
ok("flushing an outbox that does not exist is harmless", Notify.flush!() == (0, 0))
ok("a tick does nothing and says so", Notify.tick() === :off)
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

# ------------------------------------------------------------ mailbox switched on
println("\n   Turning the mailbox on")
write(CONFIG, """
to = "owner@example.invalid"
from = "clinic@example.invalid"
smtp = "smtps://smtp.example.invalid:465"
user = "clinic@example.invalid"
password = "$(PASSWORD)"
subject_prefix = "ldgr: "
send_at = "18:30"
""")
Notify.TRANSPORT[] = capture
ok("email is on", Notify.enabled() === true)
ok("and the owner is named for the startup line",
   Notify.recipient() == "owner@example.invalid")

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

# Still today, but two hours ago — the report at 6:30 pm has already gone out.
backdate!(Date(2026, 2, 8), Hour(2))

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
# 15. Which report is owed
# =============================================================================
println("\n15. The 6:30 pm cutoff")

const AT = Time(18, 30)
ok("at 6:29 pm the report owed is yesterday's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 18, 29), AT) == DateTime(2026, 2, 19, 18, 30))
ok("at 6:30 pm exactly it is today's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 18, 30), AT) == DateTime(2026, 2, 20, 18, 30))
ok("at 6:31 pm it is still today's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 18, 31), AT) == DateTime(2026, 2, 20, 18, 30))
ok("just after midnight it is yesterday's",
   Notify.latest_cutoff(DateTime(2026, 2, 20, 0, 1), AT) == DateTime(2026, 2, 19, 18, 30))

# =============================================================================
# 16. The tick that decides whether to send
# =============================================================================
println("\n16. One tick a minute, one report a day")

empty!(SENT)
Notify.TRANSPORT[] = capture
Notify.mark_reported!(DateTime(2026, 2, 20, 18, 30))
ok("the marker can be read back",
   Notify.last_reported() == DateTime(2026, 2, 20, 18, 30))

res = Notify.tick(at = DateTime(2026, 2, 20, 18, 45))
ok("a tick after the report has gone does nothing", res === :idle)
ok("and sends nothing", isempty(SENT))

res = Notify.tick(at = DateTime(2026, 2, 21, 18, 31))
ok("the next day's tick acts", res !== :idle)
ok("and the report goes out", res === :sent)
ok("exactly one report", length(SENT) == 1)
ok("addressed to the owner", SENT[end][1] == "owner@example.invalid")
ok("the marker moved on when it was queued, not when it was sent",
   Notify.last_reported() == DateTime(2026, 2, 21, 18, 30))
ok("the outbox is empty", isempty(outbox()))
ok("and the message is kept as proof it went", !isempty(sentbox()))

res = Notify.tick(at = DateTime(2026, 2, 21, 18, 31))
ok("a second tick in the same minute queues nothing", res === :idle)
ok("and nothing else was sent", length(SENT) == 1)

# =============================================================================
# 17. Catching up after the program was off
# =============================================================================
println("\n17. Three days with the program switched off")

empty!(SENT)
Notify.mark_reported!(DateTime(2026, 2, 18, 18, 30))
res = Notify.tick(at = DateTime(2026, 2, 21, 18, 40))
ok("the missed report goes out", res === :sent)
ok("as ONE report, not three", length(SENT) == 1)
ok("covering the whole window, not just the last day",
   occursin("18 February", SENT[end][3]) && occursin("21 February", SENT[end][3]))
ok("and the marker is up to date",
   Notify.last_reported() == DateTime(2026, 2, 21, 18, 30))

# =============================================================================
# 18. When the message cannot be sent
# =============================================================================
println("\n18. The mail server cannot be reached")

empty!(SENT)
kept = length(sentbox())
Notify.TRANSPORT[] = (to, subject, body) ->
    error("could not reach the mail server (user clinic@example.invalid password $(PASSWORD))")

Notify.mark_reported!(DateTime(2026, 2, 21, 18, 30))
res = Notify.tick(at = DateTime(2026, 2, 22, 18, 31))
ok("the report is still built and queued", res === :queued)
ok("and it is waiting in the outbox", length(outbox()) == 1)

queued = read(joinpath(Layout.outbox_dir(), outbox()[1]), String)
ok("with the attempt counted against it", occursin("Attempts: 1", queued))
ok("nothing new was filed as sent", length(sentbox()) == kept)
ok("nothing reached the transport", isempty(SENT))

log = auditlog()
ok("the failure is in the audit log", occursin("email NOT sent", log))
ok("THE PASSWORD IS NOWHERE IN THE AUDIT LOG", !occursin(PASSWORD, log))
ok("and nowhere in the queued message either", !occursin(PASSWORD, queued))
ok("the marker still moved, so tomorrow's report is its own",
   Notify.last_reported() == DateTime(2026, 2, 22, 18, 30))

println("\n   When it can be reached again")
Notify.TRANSPORT[] = capture
s, f = Notify.flush!()
ok("the next flush sends what was stuck", (s, f) == (1, 0))
ok("the outbox is empty", isempty(outbox()))
ok("and the message is filed", length(sentbox()) == kept + 1)

log = auditlog()
ok("the audit log names the recipient", occursin("email sent to owner@example.invalid", log))
ok("and the subject that went with it", occursin(SENT[end][2], log))

# =============================================================================
# 19. When the email package is not installed
# =============================================================================
println("\n19. SMTPClient is not installed on this machine")

const MISSING = "Email is configured but the SMTPClient package is not installed. " *
                "Run Pkg.add(\"SMTPClient\") in this Julia, or take the `to` line out of notify.toml."
empty!(SENT)
kept = length(sentbox())
Notify.TRANSPORT[] = (to, subject, body) -> error(MISSING)

saved_ok = save(day(Date(2026, 2, 12); o = 3000.0, s = 500.0, c = 3000.0,
                    reason = "Could not locate"))
ok("a day still saves with the email broken", saved_ok.out.ok)
ok("and its row is in the log", text(last_row(Date(2026, 2, 12)).what) == "saved")

Notify.mark_reported!(DateTime(2026, 2, 22, 18, 30))
res = Notify.tick(at = DateTime(2026, 2, 23, 18, 31))
ok("the report is built and queued anyway", res === :queued)
ok("and stays in the outbox", length(outbox()) == 1)
ok("nothing was filed as sent", length(sentbox()) == kept)

log = auditlog()
ok("the audit log says what is wrong, in plain words",
   occursin("SMTPClient package is not installed", log))
ok("and tells the owner what to do about it",
   occursin("Pkg.add(\"SMTPClient\")", log))
ok("still no password anywhere in it", !occursin(PASSWORD, log))

println("\n", repeat("=", 74))
println("  PASSED $(PASS[])   FAILED $(FAIL[])")
println(repeat("=", 74))
exit(FAIL[] == 0 ? 0 : 1)
