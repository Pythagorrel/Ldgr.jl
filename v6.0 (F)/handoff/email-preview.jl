# =============================================================================
# email-preview.jl — the daily report, built for a set of scenarios at FIXED
# times, and written out so it can be looked at and compared.
#
# Run (from v4.0, or from a flattened copy of it holding main.jl):
#
#   LEDGER_ROOT=<scratch folder> julia --startup-file=no handoff/email-preview.jl <out folder>
#
# For each scenario it writes <out>/<name>.subject.txt and <out>/<name>.txt, and
# <out>/<name>.html once the report has an HTML body (`Notify._report`).
#
# WHAT IT IS FOR. The plain text of the report is the record, and the HTML is a
# second rendering of the same facts. Run this before a change to the report
# code and after it, and `diff` the .txt and .subject.txt files: they must be
# byte for byte the same. Open the .html files in a browser to look at them.
#
# SAMPLES MODE. `julia handoff/email-preview.jl samples <out folder>` writes the
# owner's sample set instead: 19 realistic reports, one per kind of day (see the
# "samples" section below). It is the same script, so it shares the helpers and
# the safety rules; the 24 golden scenarios are not run in that mode.
#
# SAFETY. It refuses to run with LEDGER_ROOT unset or naming a folder called
# "Records". It EMPTIES the contents of LEDGER_ROOT before each scenario (the
# books are rebuilt with real saves, so waiting ledgers and prior-day closings
# are real). It sets LDGR_NO_DIGEST and LDGR_NOTIFY_CONFIG itself, so nothing is
# ever handed to Resend, and it never loads Resend.jl.
#
# Every save is made at a fixed moment (`Changes.after_save`'s `at`) and the
# report windows are fixed, so the output does not depend on the clock. The
# person who saved is set from the USERNAME variable, fixed here as well.
# =============================================================================

using Dates

const SCRATCH = get(ENV, "LEDGER_ROOT", "")
isempty(SCRATCH) &&
    error("Set LEDGER_ROOT to a scratch folder before running this. Without it " *
          "everything is written under v4.0/Records, which holds the real books.")
occursin("Records", SCRATCH) &&
    error("LEDGER_ROOT contains \"Records\". Point it at a scratch folder.")
isempty(ARGS) && error("Usage: julia email-preview.jl [samples] <out folder>")
const MODE = ARGS[1] == "samples" ? :samples : :scenarios
const OUT = abspath(ARGS[end])

mkpath(SCRATCH)
ENV["LDGR_NO_DIGEST"]     = "1"
ENV["LDGR_NOTIFY_CONFIG"] = joinpath(SCRATCH, "no-such-notify.toml")
ENV["LDGR_NO_BROWSER"]    = "1"
ENV["USERNAME"]           = "reception"

const HERE = @__DIR__
include(isfile(joinpath(HERE, "main.jl")) ? joinpath(HERE, "main.jl") :
        joinpath(HERE, "..", "main.jl"))

occursin("Records", Layout.ROOT) && error("Layout.ROOT resolved to a Records folder. Refusing to run.")
mkpath(OUT)

# ------------------------------------------------------------------- helpers
function reset!(who = "reception")
    mkpath(Layout.ROOT)
    for f in readdir(Layout.ROOT; join = true)
        rm(f; recursive = true, force = true)
    end
    ENV["USERNAME"] = who
    return nothing
end

function day(d; o = 1000.0, s = 0.0, e = 0.0, dep = 0.0, b = 0.0, c = 1000.0,
             scotia = NaN, taxi = NaN, reason = "", opening_reason = "")
    a = blank_amounts()
    a[:opening_balance] = o; a[:closing_balance] = c
    a[:cash_sales] = s; a[:doctor_fees] = e; a[:deposits] = dep; a[:Mr_Boyle] = b
    isnan(scotia) || (a[:POS_Scotia] = scotia)
    isnan(taxi)   || (a[:taxi_fare] = taxi)
    DayRecord(d, a, STATUS_TRADING, reason, opening_reason)
end

"One real save at a fixed moment, as the two front doors do it."
function sv(rec, t::DateTime; genesis = false)
    d = rec.date
    before = (in_books      = Chain.on_record(d),
              next_in_books = Chain.on_record(d + Day(1)),
              ledger_exists = isfile(daily_ledger_path(d)))
    previous = before.in_books ? Chain.saved_record(d) : nothing
    out = process_day(rec; echo = false, force = true, allow_genesis = genesis)
    Changes.after_save(out; rec = rec, previous = previous, before = before, at = t)
    return out
end

T(y, m, d, h, mi = 0, s = 0) = DateTime(y, m, d, h, mi, s)

"Build (subject, text, html-or-nothing) the way the code under test can."
function build(rows, problem, from, to; note = "", corrected = false)
    if isdefined(Notify, :_report)
        s, t, h = Notify._report(rows, problem, from, to; note = note, corrected = corrected)
        return (s, t, h)
    end
    s, t = Notify._digest(rows, problem, from, to; note = note, corrected = corrected)
    return (s, t, nothing)
end

"The report for a window, read from the change log."
function real(from, to; note = "", corrected = false)
    rows, problem = Changes.rows_checked(from, to)
    return build(rows, problem, from, to; note = note, corrected = corrected)
end

const RESULTS = Dict{String,Any}()
function emit(name, (s, t, h))
    write(joinpath(OUT, name * ".subject.txt"), s)
    write(joinpath(OUT, name * ".txt"), t)
    h === nothing || write(joinpath(OUT, name * ".html"), h)
    RESULTS[name] = (s, t, h)
    println("  ", rpad(name, 34), length(codeunits(t)), " B text", h === nothing ? "" : ", $(length(codeunits(h))) B html")
end

# A window for the evening of 28 September 2026 (the 5:30 pm reports).
const F28 = T(2026, 9, 27, 17, 30)
const T28 = T(2026, 9, 28, 17, 30)
const T29 = T(2026, 9, 29, 17, 30)

# ------------------------------------------------------- samples (owner's set)
# `email-preview.jl samples <out folder>` writes ONE realistic report per kind
# of day, for the owner to read on a phone: NN-name.html, .txt and .subject.txt.
# Books are built with real saves at fixed times in the week of 21-29 September
# 2026 (Mon-Sat; the clinic is closed on Sundays). A report covers the stretch
# from the previous 5:30 pm send time to this one, except where the case is
# several days by nature. Figures are multiples of 1000.

"The report for the ordinary window ending at 5:30 pm on `d`."
ordinary(d::Date; note = "", corrected = false) =
    real(DateTime(d - Day(1)) + Hour(17) + Minute(30), DateTime(d) + Hour(17) + Minute(30);
         note = note, corrected = corrected)

const SAMPLE_ROOT_SHOWN = raw"E:\Ldgr\v4.0\Records"

"""
Write one sample. The body prints `Records folder: <Layout.ROOT>`, which here is
a scratch folder; the OWNER should see the real place instead. So, in the SAMPLE
output only (Notify.jl is untouched and still prints what it is given), the
scratch path is swapped for E:\\Ldgr\\v4.0\\Records before the file is written.
"""
function sample_out(name, (s, t, h))
    fix(x) = x === nothing ? nothing : replace(String(x), Layout.ROOT => SAMPLE_ROOT_SHOWN)
    s, t, h = fix(s), fix(t), fix(h)
    write(joinpath(OUT, name * ".subject.txt"), s)
    write(joinpath(OUT, name * ".txt"), t)
    h === nothing || write(joinpath(OUT, name * ".html"), h)
    println("  ", rpad(name, 36), length(codeunits(t)), " B text, ", h === nothing ? 0 : length(codeunits(h)), " B html")
end

"""
The emails the scheduler itself builds, through `Notify.tick` at fixed moments,
with a fake mailer that keeps what it is handed (nothing leaves the machine:
Resend.jl is never loaded). `steps(made)` does the ticks; returns the emails
created, in order.
"""
function ticking(steps; marker)
    cfgdir = mktempdir()
    cfg = joinpath(cfgdir, "notify-samples.toml")
    write(cfg, "to = \"owner@example.invalid\"\napi_key = \"re_samplesamplesample0000\"\n" *
               "from = \"LDGR Daily Report <reports@example.invalid>\"\n")
    ENV["LDGR_NOTIFY_CONFIG"] = cfg
    made = Any[]
    ids = Ref(0)
    Notify.MAILER[] = (send = (key, email, idem) -> (push!(made, deepcopy(Dict{String,Any}(email)));
                                                     "sample-$(ids[] += 1)"),
                       cancel = (key, id) -> nothing)
    rm(Layout.scheduled_state_path(); force = true)
    rm(Layout.digest_marker_path(); force = true)
    Notify.mark_reported!(marker)
    Notify.BACKOFF[] = nothing; Notify.CANCEL_BACKOFF[] = nothing
    try
        steps(made)
    finally
        Notify.MAILER[] = nothing
        ENV["LDGR_NOTIFY_CONFIG"] = joinpath(SCRATCH, "no-such-notify.toml")
        rm(cfgdir; recursive = true, force = true)
    end
    return made
end

"(subject, text, html) of an email the fake mailer kept."
mailed(e) = (String(e["subject"]), String(e["text"]), String(get(e, "html", "")))

function run_samples()
    println("Writing samples to $(OUT)")
    # The usual lead-in: Monday 21 and Tuesday 22 September, one balanced day
    # each, so that the days after have a day before to open from.
    mon, tue, wed, thu, fri, sat = (Date(2026, 9, d) for d in 21:26)
    lead!() = (sv(day(mon; o = 10000.0, s = 14000.0, e = 5000.0, dep = 0.0, c = 19000.0),
                  T(2026, 9, 21, 16, 20); genesis = true);
               sv(day(tue; o = 19000.0, s = 15000.0, e = 5000.0, dep = 9000.0, c = 20000.0),
                  T(2026, 9, 22, 16, 25)))

    # 01. One Work day, balanced.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, taxi = 1000.0, c = 19000.0),
       T(2026, 9, 23, 16, 40))
    sample_out("01-normal-day", ordinary(wed))

    # 02. Saved, then corrected before that evening's send time.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 15, 40))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 17000.0, e = 6000.0, dep = 10000.0, c = 21000.0), T(2026, 9, 23, 16, 35))
    sample_out("02-corrected-same-session", ordinary(wed))

    # 03. A shortage, with its reason.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    sv(day(thu; o = 20000.0, s = 18000.0, e = 7000.0, dep = 9000.0, c = 20000.0,
           reason = "Paid the lab courier from the drawer"), T(2026, 9, 24, 16, 50))
    sample_out("03-does-not-balance-shortage", ordinary(thu))

    # 04. A surplus, with its reason.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    sv(day(thu; o = 20000.0, s = 17000.0, e = 6000.0, dep = 9000.0, c = 23000.0,
           reason = "A patient left change on the counter and did not come back"), T(2026, 9, 24, 16, 55))
    sample_out("04-does-not-balance-surplus", ordinary(thu))

    # 05. The opening differs from the day before's close; the day balances.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    sv(day(thu; o = 18000.0, s = 17000.0, e = 6000.0, dep = 9000.0, c = 20000.0,
           opening_reason = "Change fund moved to the safe overnight"), T(2026, 9, 24, 16, 45))
    sample_out("05-opening-mismatch", ordinary(thu))

    # 06. A shortage in yesterday's report, corrected today so that it balances.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 15000.0, e = 5000.0, dep = 8000.0, c = 20000.0,
           reason = "Could not find the difference at closing"), T(2026, 9, 23, 16, 30))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 15000.0, e = 7000.0, dep = 8000.0, c = 20000.0), T(2026, 9, 24, 10, 5))
    sample_out("06-now-balances", ordinary(thu))

    # 07. A balanced day edited on a later date; figures move and it still balances.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 17000.0, e = 6000.0, dep = 10000.0, c = 21000.0), T(2026, 9, 24, 9, 15))
    sample_out("07-edited-after-report", ordinary(thu))

    # 08. Saved at 6:10 pm, after that day's 5:30 pm report; corrected at 9:20 am
    #     the next morning, before the next report, so both rows are in one report.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 18, 10))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 17000.0, e = 6000.0, dep = 10000.0, c = 21000.0), T(2026, 9, 24, 9, 20))
    sample_out("08-saved-after-1730-edited-after-midnight", ordinary(thu))

    # 09. An edit to a day whose ledger was waiting on a missing day. Monday is
    #     the first day; Tuesday is never typed; Wednesday is held, then edited.
    reset!()
    sv(day(mon; o = 10000.0, s = 14000.0, e = 5000.0, dep = 0.0, c = 19000.0), T(2026, 9, 21, 16, 20); genesis = true)
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 14, 0))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 17000.0, e = 6000.0, dep = 10000.0, c = 21000.0), T(2026, 9, 23, 16, 50))
    sample_out("09-pending-day-edit", ordinary(wed))

    # 10. An Off day.
    reset!(); lead!()
    sv(closed_day(wed, 20000.0), T(2026, 9, 23, 16, 30))
    sample_out("10-off-day", ordinary(wed))

    # 11. A day typed as a Work day, switched to an Off day on a later date.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 0.0, e = 0.0, dep = 0.0, c = 20000.0), T(2026, 9, 23, 16, 30))
    ENV["USERNAME"] = "manager"
    sv(closed_day(wed, 20000.0), T(2026, 9, 24, 9, 40))
    sample_out("11-kind-of-day-changed", ordinary(thu))

    # 12. The missing day is entered, releasing the waiting ledger of the day after.
    reset!()
    sv(day(mon; o = 10000.0, s = 14000.0, e = 5000.0, dep = 0.0, c = 19000.0), T(2026, 9, 21, 16, 20); genesis = true)
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    ENV["USERNAME"] = "manager"
    sv(day(tue; o = 19000.0, s = 15000.0, e = 5000.0, dep = 9000.0, c = 20000.0), T(2026, 9, 24, 8, 50))
    sample_out("12-gap-filled", ordinary(thu))

    # 13. A day saved after a missing day, so its ledger waits.
    reset!()
    sv(day(mon; o = 10000.0, s = 14000.0, e = 5000.0, dep = 0.0, c = 19000.0), T(2026, 9, 21, 16, 20); genesis = true)
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    sample_out("13-ledgers-waiting", ordinary(wed))

    # 14. Nothing entered or changed.
    reset!(); lead!()
    sample_out("14-quiet-day", ordinary(wed))

    # 15. The change log has a damaged line. The technique of tests/test_notify.jl
    #     group 33: a row cut off after its journal cell, appended by hand.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 10))
    open(Layout.change_log_path(), "a") do io
        write(io, "2026-09-23 16:55:00,reception,saved,2026-09-23,trading,added\n")
    end
    sample_out("15-change-log-unreadable", ordinary(wed))

    # 16. A late report, for days typed while nothing was sent. Three days were
    #     entered Wed-Fri with no report handed over; ldgr is opened on
    #     Saturday morning, and the scheduler sends what nobody covered.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 5))
    sv(day(thu; o = 20000.0, s = 18000.0, e = 7000.0, dep = 9000.0, c = 20000.0,
           reason = "Paid the lab courier from the drawer"), T(2026, 9, 24, 16, 20))
    sv(closed_day(fri, 20000.0), T(2026, 9, 25, 15, 50))
    made = ticking(; marker = T(2026, 9, 22, 17, 30)) do made
        Notify.tick(at = T(2026, 9, 26, 8, 45))
    end
    i = findfirst(e -> occursin("This report is late", String(e["text"])), made)
    i === nothing && error("no late report was produced; got $(length(made)) email(s)")
    sample_out("16-late-several-days", mailed(made[i]))

    # 17. A corrected report: a day was handed over at 3:50 pm, a save landed at
    #     5:05 pm that could not be handed over (the network was down), and the
    #     first tick after 5:30 pm sends a replacement.
    reset!(); lead!()
    made = ticking(; marker = T(2026, 9, 22, 17, 30)) do made
        sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 15, 45))
        Notify.tick(at = T(2026, 9, 23, 15, 50))
        ENV["USERNAME"] = "manager"
        sv(day(wed; o = 20000.0, s = 17000.0, e = 6000.0, dep = 10000.0, c = 21000.0), T(2026, 9, 23, 17, 5))
        Notify.tick(at = T(2026, 9, 23, 17, 42))
    end
    i = findfirst(e -> occursin("corrected report", String(e["subject"])), made)
    i === nothing && error("no corrected report was produced; got $(length(made)) email(s)")
    sample_out("17-corrected-report", mailed(made[i]))

    # 18. Both differences on one day, each with its own explanation: the opening
    #     is MORE than the last close, and the closing count is short.
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    sv(day(thu; o = 21000.0, s = 17000.0, e = 6000.0, dep = 9000.0, c = 22000.0,
           reason = "Paid the lab courier from the drawer",
           opening_reason = "Change fund moved to the safe overnight"), T(2026, 9, 24, 16, 50))
    sample_out("18-both-differences", ordinary(thu))

    # 19. A balanced day revised on a later date so that it now has a closing-count
    #     shortage (a revision cannot be saved without its explanation).
    reset!(); lead!()
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 20000.0), T(2026, 9, 23, 16, 40))
    ENV["USERNAME"] = "manager"
    sv(day(wed; o = 20000.0, s = 16000.0, e = 6000.0, dep = 10000.0, c = 19000.0,
           reason = "Counted again in the morning; the drawer is short"), T(2026, 9, 24, 9, 15))
    sample_out("19-revised-still-unbalanced", ordinary(thu))

    # (There is no sample of a difference with no explanation, because a real save
    # cannot make one: both front doors refuse a day whose difference has no reason
    # (`Checks.unexplained`), and `_retry_pending!` holds a waiting ledger whose
    # recomputed difference has none instead of releasing it. The "no explanation
    # given" wording is exercised by tests/test_notify.jl with constructed rows.)
    println("Done: 19 samples.")
end

MODE === :samples && (run_samples(); exit(0))

# --------------------------------------------------------------- scenarios
println("Writing scenarios to $(OUT)")

# 1. Nothing at all.
reset!()
emit("s01-quiet-no-rows", real(F28, T28))

# 2. One balanced Work day.
reset!()
sv(day(Date(2026, 9, 28); o = 1000.0, s = 500.0, e = 100.0, c = 1400.0), T(2026, 9, 28, 16, 10); genesis = true)
emit("s02-one-balanced-day", real(F28, T28))

# 3. An Off day (after a Work day the day before, outside the window).
reset!()
sv(day(Date(2026, 9, 27); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 27, 16, 0); genesis = true)
sv(closed_day(Date(2026, 9, 28), 1500.0), T(2026, 9, 28, 16, 30))
emit("s03-off-day", real(F28, T28))

# 4. A shortage with its reason, and an opening that is less than the last close.
reset!()
sv(day(Date(2026, 9, 27); o = 1000.0, s = 2000.0, c = 3000.0), T(2026, 9, 27, 16, 0); genesis = true)
sv(day(Date(2026, 9, 28); o = 2500.0, s = 1000.0, c = 2500.0,
       reason = "Paid the lab courier from the drawer; the receipt is in the folder.",
       opening_reason = "Change fund moved to the safe overnight."), T(2026, 9, 28, 17, 2))
emit("s04-shortage-and-opening-less", real(F28, T28))

# 5. A surplus and an opening that is more than the last close.
reset!()
sv(day(Date(2026, 9, 27); o = 1000.0, s = 2000.0, c = 3000.0), T(2026, 9, 27, 16, 0); genesis = true)
sv(day(Date(2026, 9, 28); o = 3200.0, s = 0.0, c = 3700.0,
       reason = "A patient left change behind.", opening_reason = "Float topped up by the manager."),
   T(2026, 9, 28, 16, 45))
emit("s05-surplus-and-opening-more", real(F28, T28))

# 6. A later edit that makes a day balance: a figure change, a "(not counted)"
#    figure, and a reason change. Saved on the 26th, edited on the 28th.
reset!()
sv(day(Date(2026, 9, 26); o = 1000.0, s = 3000.0, scotia = 12000.0, c = 5000.0, reason = "Could not locate"),
   T(2026, 9, 26, 16, 20); genesis = true)
ENV["USERNAME"] = "manager"
sv(day(Date(2026, 9, 26); o = 1000.0, s = 3000.0, scotia = 13000.0, taxi = 2000.0, c = 2000.0),
   T(2026, 9, 28, 10, 5))
emit("s06-edit-makes-balance", real(F28, T28))

# 6b. A later edit that changes the kind of day, a reason, and leaves a
#     difference standing.
reset!()
sv(day(Date(2026, 9, 26); o = 1000.0, s = 500.0, c = 1400.0, reason = "Short"),
   T(2026, 9, 26, 16, 20); genesis = true)
ENV["USERNAME"] = "manager"
sv(day(Date(2026, 9, 26); o = 1000.0, s = 500.0, c = 1300.0, reason = "Change given to a patient"),
   T(2026, 9, 28, 9, 30))
sv(closed_day(Date(2026, 9, 26), 1000.0), T(2026, 9, 28, 9, 45))
emit("s06b-edit-kind-and-reason", real(F28, T28))

# 7. A pending-day edit: day 27 is held (25 and 26 are missing) and is edited
#    the same day.
reset!()
sv(day(Date(2026, 9, 24); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 24, 16, 0); genesis = true)
sv(day(Date(2026, 9, 27); o = 2000.0, s = 500.0, c = 2500.0), T(2026, 9, 27, 16, 0))
ENV["USERNAME"] = "manager"
sv(day(Date(2026, 9, 27); o = 2000.0, s = 700.0, c = 2700.0), T(2026, 9, 27, 16, 40))
emit("s07-pending-day-edit", real(T(2026, 9, 26, 17, 30), T(2026, 9, 27, 17, 30)))

# 8. Ledgers still waiting, with nothing new in the window.
reset!()
sv(day(Date(2026, 9, 24); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 24, 16, 0); genesis = true)
sv(day(Date(2026, 9, 27); o = 2000.0, s = 500.0, c = 2500.0), T(2026, 9, 27, 16, 0))
sv(day(Date(2026, 9, 26); o = 2000.0, s = 500.0, c = 2500.0), T(2026, 9, 26, 16, 0))  # a second held day
emit("s08-ledgers-waiting-only", real(T28, T29))

# 9. A gap filled that releases a ledger, with differences found on release.
#    24 is the first day; 27 was typed while 25 and 26 were missing (a shortage
#    of its own, and an opening that will not match 26); then 25 and 26 are typed.
function gap_books(; gap_short = false)
    reset!()
    sv(day(Date(2026, 9, 24); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 24, 16, 0); genesis = true)
    sv(day(Date(2026, 9, 27); o = 2000.0, s = 500.0, c = 2300.0, reason = "Lab courier paid in cash.",
           opening_reason = "Change fund moved to the safe overnight."), T(2026, 9, 27, 16, 0))
    ENV["USERNAME"] = "manager"
    sv(day(Date(2026, 9, 25); o = 1500.0, s = 500.0, c = 2000.0), T(2026, 9, 28, 8, 55))
    if gap_short
        sv(day(Date(2026, 9, 26); o = 2000.0, s = 500.0, c = 2100.0, reason = "Coins short in the drawer."),
           T(2026, 9, 28, 9, 5))
    else
        sv(day(Date(2026, 9, 26); o = 2000.0, s = 500.0, c = 2500.0), T(2026, 9, 28, 9, 5))
    end
end
gap_books()
emit("s09-gap-filled-releases", real(T(2026, 9, 27, 17, 30), T28))
gap_books(gap_short = true)
emit("s09b-gap-day-with-difference", real(T(2026, 9, 27, 17, 30), T28))

# 9c. A backlog typed in backwards: 26 (held) and 27 (held), then 25 fills the
#     gap and releases both.
reset!()
sv(day(Date(2026, 9, 24); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 24, 16, 0); genesis = true)
sv(day(Date(2026, 9, 26); o = 2000.0, s = 500.0, c = 2500.0), T(2026, 9, 26, 16, 0))
sv(day(Date(2026, 9, 27); o = 2500.0, s = 500.0, c = 3000.0), T(2026, 9, 27, 16, 0))
ENV["USERNAME"] = "manager"
sv(day(Date(2026, 9, 25); o = 1500.0, s = 500.0, c = 2000.0), T(2026, 9, 28, 9, 0))
emit("s09c-gap-two-released", real(T(2026, 9, 27, 17, 30), T28))

# 10. Only same-date corrections in the window (quiet, with rows).
reset!()
sv(day(Date(2026, 9, 28); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 28, 15, 0); genesis = true)
sv(day(Date(2026, 9, 28); o = 1000.0, s = 600.0, c = 1600.0), T(2026, 9, 28, 16, 0))
emit("s10-same-date-corrections-only", real(T(2026, 9, 28, 15, 30), T28))

# 11/12. An unreadable change log, quiet and not quiet.
PROBLEM = "Line 3 of Change Log.csv (counting the heading as line 1) could not be read and was left out."
reset!()
emit("s11-unreadable-quiet", build(Changes.Row[], PROBLEM, F28, T28))
reset!()
sv(day(Date(2026, 9, 28); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 28, 16, 10); genesis = true)
rows, _ = Changes.rows_checked(F28, T28)
emit("s12-unreadable-not-quiet", build(rows, PROBLEM, F28, T28))

# 13. The notes.
reset!()
sv(day(Date(2026, 9, 28); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 28, 16, 10); genesis = true)
emit("s13a-note-late",
     real(F28, T28; note = "This report is late: it could not be sent at 5:30 pm, usually because ldgr " *
                           "was closed or offline before it could hand the report over."))
emit("s13b-note-corrected",
     real(F28, T28; corrected = true,
          note = "This replaces the report sent at 5:30 pm, which was prepared before the last entry " *
                 "of that day could be sent."))
emit("s13c-note-follow-up",
     real(F28, T28; note = "This follows the report sent at 5:30 pm. When ldgr checked it afterwards, " *
                           "part of the change log for that stretch could not be read, so that report " *
                           "may have left an entry out."))
emit("s13d-span", real(T(2026, 9, 25, 17, 30), T28))
emit("s13e-late-and-span",
     real(T(2026, 9, 25, 17, 30), T28;
          note = "This report is late: it could not be sent at 5:30 pm, usually because ldgr was " *
                 "closed or offline before it could hand the report over."))

# 14. A hostile reason (and who), on a first save and in a later edit.
reset!("O'Brien <admin> & co")
HOSTILE = "<script>alert(1)</script> & \"quotes\" 'apostrophe'; semi; colons é — \U0001F600"
sv(day(Date(2026, 9, 26); o = 1000.0, s = 500.0, c = 1400.0, reason = HOSTILE), T(2026, 9, 26, 16, 0); genesis = true)
sv(day(Date(2026, 9, 27); o = 1400.0, s = 500.0, c = 1900.0), T(2026, 9, 27, 16, 0))
sv(day(Date(2026, 9, 27); o = 1400.0, s = 500.0, c = 1800.0, reason = HOSTILE), T(2026, 9, 28, 9, 0))
emit("s14-hostile-text", real(T(2026, 9, 25, 17, 30), T28))
# and the opening reason
reset!()
sv(day(Date(2026, 9, 27); o = 1000.0, s = 500.0, c = 1500.0), T(2026, 9, 27, 16, 0); genesis = true)
sv(day(Date(2026, 9, 28); o = 900.0, s = 500.0, c = 1400.0, opening_reason = HOSTILE), T(2026, 9, 28, 16, 0))
emit("s14b-hostile-opening-reason", real(F28, T28))

# 15. Constructed rows, for what a real save cannot reach: no day before to
#     compare with (a missing prior day), a release whose saving row cannot be
#     read, and an edit whose changed text the report cannot parse.
reset!()
function row(when, d; what = "saved", kind = "trading", ledger = "written", dd = 0.0, nd = 0.0,
             reason = "", nreason = "", wdd = NaN, wnd = NaN, changed = "", cross = false,
             pend = false, bal = false, gap = false, by = nothing, who = "reception")
    Changes.Row((when, who, what, d, kind, what == "edited" ? "replaced" : (what == "released" ? "" : "added"),
                 ledger, dd, nd, reason, nreason, wdd, wnd, changed, cross, pend, bal, gap, by))
end
rows = Changes.Row[
    row(T(2026, 9, 28, 16, 0), Date(2026, 9, 28); nd = -300.0, nreason = "Float moved"),
    row(T(2026, 9, 28, 16, 5), Date(2026, 9, 20); what = "released", dd = 200.0, reason = "Found in the safe",
        nd = 50.0, by = Date(2026, 9, 19)),
    row(T(2026, 9, 28, 16, 6), Date(2026, 9, 21); what = "edited", changed = "", cross = true,
        pend = true),
    row(T(2026, 9, 28, 16, 7), Date(2026, 9, 22); what = "edited", cross = true,
        changed = "Something the report cannot parse <b>; Reason \"a\" -> \"b\"; Taxi Fare \$1.00 -> \$2.00; Kind of day closed -> trading"),
    row(T(2026, 9, 28, 16, 7, 30), Date(2026, 9, 24); what = "edited", cross = true, bal = true, wdd = -50.0,
        changed = "Taxi Fare (not counted) -> \$2,000.00; Doctor's Fees \$10.00 -> (not counted); Reason \"\" -> \"Found it\"; Night reason \"x\" -> \"\""),
    row(T(2026, 9, 28, 16, 8), Date(2026, 9, 23); what = "released", dd = -100.0, reason = "  ", nd = 0.0,
        by = Date(2026, 9, 23) - Day(2)),
]
emit("s15-constructed-rows", build(rows, "", F28, T28))

# 16. Thirty-one balanced days in one window (the size budget).
reset!()
let d0 = Date(2026, 8, 1), bal = 1000.0
    for i in 0:30
        d = d0 + Day(i)
        sv(day(d; o = bal, s = 700.0 + i, e = 100.0, c = bal + 600.0 + i), T(year(d), month(d), Dates.day(d), 16, 10);
           genesis = i == 0)
        bal += 600.0 + i
    end
end
emit("s16-thirty-one-days", real(T(2026, 7, 31, 17, 30), T(2026, 8, 31, 17, 30)))

println("Done: $(length(RESULTS)) scenarios.")
