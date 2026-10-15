module Layout

using Dates

# =============================================================================
# LAYOUT — every folder path and filename in the system is built here.
#
# ENTIRELY NEW FILE. v2.1.1 built its paths inline in the driver:
#     ledger_dir = "$(y)_ledgers"; daily_dir = "$(y)_daily_records"
#     mkpath(ledger_dir); mkpath(daily_dir)
# Those two lines are superseded by this module. Nothing outside this file is
# permitted to construct a path — that is what makes the folder rules
# changeable in one place.
#
# TWO CORRECTIONS TO THE SPEC AS WRITTEN:
#   1. "m/year" cannot be a filename — `/` is the path separator on every OS.
#      Folders nest as <ROOT>/<year>/<mm>/ and filenames use `-` as the
#      separator instead.
#   2. Months and days are zero-padded and dates are written year-first, so
#      that alphabetical sorting in a file browser equals chronological order.
#      "09-2026" sorts before "10-2026"; "9-2026" would not.
# =============================================================================

export ROOT, month_tag, iso_tag,
       year_dir, month_dir, journal_path, monthly_ledger_path,
       daily_ledger_dir, daily_ledger_path, warmup_file,
       ensure_month_dir, ensure_daily_ledger_dir

# NEW. v2.1.1 wrote relative to `pwd()`, which is whatever directory the
# program happened to be launched from — so double-clicking it vs. running it
# from a terminal scattered files in two different places. ROOT is now an
# absolute path anchored to the source folder, overridable by an environment
# variable for testing or for pointing at a shared drive.
#   @__DIR__  — the directory containing this source file.
#   get(ENV, k, default) — returns ENV[k] if the variable is set, else default.
#
# v6.0: ROOT is read when the module is initialised (`__init__`), not when the
# file is compiled. The packaged app compiles this file into a system image on
# the developer's PC; a `const` would freeze the build machine's folder into it
# and the clinic's LEDGER_ROOT would be ignored. Loaded from source, as in
# development and the tests, `__init__` runs as soon as the module is defined,
# so ROOT is set exactly as before.
ROOT::String = ""
_root_from_env() = get(ENV, "LEDGER_ROOT", joinpath(@__DIR__, "Records"))
function __init__()
    global ROOT = _root_from_env()
    return nothing
end

# --- Name fragments --------------------------------------------------------
# lpad(9, 2, '0') => "09". Applied to months and days everywhere.
pad2(n::Integer) = lpad(n, 2, '0')

"Month stamp used in month-scoped filenames, e.g. 09-2026."
month_tag(y::Integer, m::Integer) = "$(pad2(m))-$(y)"

"Date stamp used in day-scoped filenames, e.g. 2026-09-14. Year-first so it sorts."
iso_tag(d::Date) = "$(year(d))-$(pad2(month(d)))-$(pad2(day(d)))"

# --- Directories -----------------------------------------------------------
year_dir(y::Integer)  = joinpath(ROOT, string(y))
month_dir(y, m)       = joinpath(year_dir(y), pad2(m))

"Folder holding the per-day ledgers for one month."
daily_ledger_dir(y, m) = joinpath(month_dir(y, m), "Daily Ledgers $(month_tag(y, m))")

# --- Files -----------------------------------------------------------------
"The month's Daily Journal — the single source of truth for that month."
journal_path(y, m) = joinpath(month_dir(y, m), "Daily Journal $(month_tag(y, m)).csv")

"The month's ledger. Derived from the journal; safe to overwrite on every run."
monthly_ledger_path(y, m) = joinpath(month_dir(y, m), "Monthly Ledger $(month_tag(y, m)).csv")

"One day's ledger."
daily_ledger_path(d::Date) =
    joinpath(daily_ledger_dir(year(d), month(d)), "Daily Ledger $(iso_tag(d)).csv")

# --- Paths that used to be built at their call sites -----------------------
# NONE OF THE NAMES BELOW ARE EXPORTED, and that is deliberate. They are called
# as `Layout.audit_log_path()` and so on, spelled out at every call site, so a
# reader can see at a glance that the path came from here and not from a
# `joinpath` somebody wrote in passing (README rule 2). `report_path` in
# particular must not be exported: Report.jl exports a `report_path` of its own
# that delegates here, and two modules exporting one name makes it ambiguous at
# every call site that does `using` on both.

"""
    audit_log_path() -> String

The one audit log, at the top of the records folder. Named here rather than at
the call site that used to build it by hand, so that moving the log is one edit
rather than a search.
"""
audit_log_path() = joinpath(ROOT, "audit_log.txt")

"Folder holding the daily reports."
reports_dir() = joinpath(ROOT, "Reports")

"""
    report_path(d) -> String

Where a day's report lands. One file per calendar day the program was run.
"""
report_path(d::Date=Dates.today()) =
    joinpath(reports_dir(), "Daily Report $(iso_tag(d)).txt")

"""
    change_log_path() -> String

The change log: `<ROOT>/Change Log.csv`, one row appended for every write to the
books — the day that was saved, and each held ledger that write released.

IT IS A NOTIFICATION RECORD, NOT PART OF THE BOOKS, exactly as the daily report
is. Nothing in the bookkeeping depends on it: the journal is still the only
source of truth, every figure it names exists independently, and deleting it
would leave the books untouched. What it adds is the one thing the journal
cannot give — a timestamp. `upsert_day!` replaces a day's row in place, so once
a figure is corrected the old one is gone; the log is where the previous figure
and the moment it changed are written down, so the daily report can say what
moved without the books having to carry a history they were never designed for.

Append-only by construction: rows are added, never rewritten.
"""
change_log_path() = joinpath(ROOT, "Change Log.csv")

"""
    recorded_months() -> Vector{Tuple{Int,Int}}

Every `(year, month)` that has a Daily Journal on disk, oldest first.

Here rather than in Chain because it is path work: it knows that months live at
`<ROOT>/<yyyy>/<mm>/` and that a month counts only once `journal_path` names a
file that exists. The caller — `Chain.waiting_ledgers` — then asks its own
question of each month without ever spelling a folder name.

Only a 4-digit year folder and a 2-digit month folder are considered, so the
`Reports` and `Notifications` folders beside them, and anything else a person
drops into the records folder, are skipped rather than parsed. A records folder
that does not exist yet is not an error — it is a fresh install, and the honest
answer is an empty list.
"""
function recorded_months()
    out = Tuple{Int,Int}[]
    isdir(ROOT) || return out
    for yname in readdir(ROOT)
        (length(yname) == 4 && all(isdigit, yname)) || continue
        ydir = joinpath(ROOT, yname)
        isdir(ydir) || continue
        y = parse(Int, yname)
        for mname in readdir(ydir)
            (length(mname) == 2 && all(isdigit, mname)) || continue
            isdir(joinpath(ydir, mname)) || continue
            m = parse(Int, mname)
            isfile(journal_path(y, m)) && push!(out, (y, m))
        end
    end
    return sort(out)
end

# --- Notifications ---------------------------------------------------------
# The email settings and the two small files that say how far the daily report
# has got. The settings live beside the program (they describe the
# installation, not the books); the two state files live under ROOT with the
# books they are about, so a records folder can be copied to another machine
# complete. There is no outbox any more: the report is handed straight to
# Resend, which holds it until the send time (see Notify.jl).

"""
    notify_config_path() -> String

The email settings, `notify.toml`, beside the source files. Absent by default,
and absent means email is simply off.

`LDGR_NOTIFY_CONFIG` overrides it, exactly as `LEDGER_ROOT` overrides ROOT, so a
test can point at a scratch file and never touch the installed settings.
"""
notify_config_path() = get(ENV, "LDGR_NOTIFY_CONFIG", joinpath(@__DIR__, "notify.toml"))

notifications_dir() = joinpath(ROOT, "Notifications")

"""
    digest_marker_path() -> String

The one line that says how far the daily report has got: the cutoff up to which
reports are known to be complete — handed to Resend and past their send time.

A FILE RATHER THAN SOMETHING HELD IN MEMORY, because the question it answers —
"has today's report already gone out?" — has to survive the server being closed
and started again, which is the ordinary case at the end of a day.
"""
digest_marker_path() = joinpath(notifications_dir(), "last report.txt")

"""
    scheduled_state_path() -> String

`scheduled report.toml`: the version of the coming report that is waiting at
Resend — its id, its send time, the stretch it covers, how many change-log rows
it was built from — and any earlier versions still to be cancelled.

It is what lets a server started at any hour pick up exactly where the last one
left off: without it, a restart could not cancel the version it had already
handed over, and the owner would get two.
"""
scheduled_state_path() = joinpath(notifications_dir(), "scheduled report.toml")

"""
    temp_path(path) -> String

The scratch name a small file is written under before it is moved into place, so
the real file is always either the old version or the new one and never half of
each. Named here, like every other path (README rule 2), and matched by the
`*.tmp` line in `.gitignore`.
"""
temp_path(path::AbstractString) = String(path) * ".tmp"

"""
    warmup_file() -> String

A scratch file for server.jl's `warmup()` to write and read back, so that the
CSV writer, the journal reader and the audit log are compiled before the first
real save.

DELIBERATELY NOT UNDER ROOT. Nothing the warm-up does may touch the books: the
whole point is that starting the server leaves the Records folder byte-for-byte
as it found it. So this lives in the OS temp folder, and the process id keeps
two servers started at once from colliding. `warmup()` deletes it in a `finally`
when it is done.

It is named here rather than built with `mktemp()` at the call site only because
of README rule 2 — no path is constructed outside this file, and a scratch path
is still a path.
"""
warmup_file() = joinpath(tempdir(), "ldgr-warmup-$(getpid()).csv")

# --- Creation --------------------------------------------------------------
# Each ensure_* returns (path, created) where `created` is true only if the
# folder did not already exist. The driver uses that flag to report what it
# had to build, which is the "checks whether a folder exists; if not,
# generates it" requirement.
#
# mkpath (unlike mkdir) creates every missing parent level in one call and is
# a no-op if the directory already exists — so <year>/ and <year>/<mm>/ are
# both handled by the single call below.

function ensure_month_dir(y, m)
    p = month_dir(y, m)
    created = !isdir(p)
    mkpath(p)
    return (p, created)
end

function ensure_daily_ledger_dir(y, m)
    p = daily_ledger_dir(y, m)
    created = !isdir(p)
    mkpath(p)
    return (p, created)
end

end # module Layout
