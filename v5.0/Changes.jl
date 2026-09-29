module Changes

using Dates, DataFrames, CSV
using ..Config
using ..Layout
using ..DayInput
using ..Checks

# =============================================================================
# CHANGES — the paper trail. One row appended for every write to the books.
#
# ENTIRELY NEW FILE. It exists because of one gap in the design, and it is worth
# stating plainly: THE BOOKS KEEP NO HISTORY. `Journal.upsert_day!` replaces a
# day's row in place, and the journal carries no timestamp column, so the moment
# a figure is corrected the figure it replaced is gone and nothing anywhere says
# it ever existed. That is right for the books — a journal is what is true now,
# not a diary — but it means the owner cannot be told what moved, and three
# things that matter are invisible today:
#
#   * a day saved a week ago, quietly edited this afternoon;
#   * a day whose ledger is held because the day before it is missing, edited
#     while it waits, before anyone has seen it posted;
#   * a day saved as not balancing, then edited until it balanced.
#
# None of those is an error, and none of them should be refused. They are simply
# facts the owner has asked to be told about, and the only place they can be
# recorded is beside the write that made them.
#
# WHAT THIS IS NOT. It is not part of the books, exactly as the daily report is
# not (see Report.jl's header, which makes the same promise). Nothing in the
# bookkeeping reads this file. Every figure in it exists independently in the
# journal, the ledgers and the audit log. Delete it and the books are untouched;
# all that is lost is the ability to say WHEN something changed.
#
# IT MUST NEVER FAIL A SAVE. The day is in the books before this file is
# touched, and a notification record that could refuse a save would be a worse
# bargain than no record at all. `after_save` therefore wraps its whole body and
# reports a failure as one warning and a return of zero. Both front doors — the
# form and the command line — call it in that spirit.
#
# IT IS WRITTEN WHETHER OR NOT EMAIL IS CONFIGURED. The log is the record; the
# email is one reader of it. A clinic that never sets up a mailbox still
# accumulates the trail, and switching email on later makes the whole of it
# readable at once.
#
# WHY A CSV, AND WHY THESE NINETEEN COLUMNS. Because the owner may one day open
# it. It is the one file in this program written for a person with a
# spreadsheet rather than for the program itself, so the headers are words
# ("day difference", "was day difference") rather than keys, they are in the
# order somebody would read them, and CSV.jl does the quoting so a reason with
# a comma in it survives the round trip. Append-only by construction: rows are
# added, never rewritten.
# =============================================================================

export after_save, rows_between, first_seen, Row, COLUMNS

"""
    COLUMNS

The nineteen headers of `Change Log.csv`, in the order they are written.

THIS ORDER IS PART OF THE FILE FORMAT. A log written last month and a log
written today must read back the same way, so columns are appended at the end
if they are ever added, never inserted or reordered. The names are what the
owner sees at the top of a spreadsheet, which is why they are lower-case words
with spaces rather than the Symbol keys used everywhere else in the program.
"""
const COLUMNS = ["when", "who", "what", "day", "day kind", "journal", "ledger",
                 "day difference", "night difference", "reason", "night reason",
                 "was day difference", "was night difference", "changed",
                 "cross day edit", "pending day", "now balances", "filled a gap",
                 "released by"]

"""
    Row

One line of the change log, in memory.

A NamedTuple with a fixed field order rather than a struct so that writing a row
and reading one back are visibly the same nineteen things in the same sequence,
and so that a mistake in either direction is a compile-time complaint about the
tuple rather than a column silently landing one place to the left.

The field names are the programmer's spelling of `COLUMNS`; `_cells` is the one
place the two vocabularies meet.

  when            the moment the save finished
  who             the Windows login that did it
  what            "saved", "edited" or "released"
  day             the business day this row is about
  kind            "trading" or "closed"
  journal         "added" / "replaced", blank on a released row
  ledger          what happened to the daily ledger
  day_diff        the difference found during the day
  night_diff      the difference between this opening and the last close
  reason          the typed explanation for the day difference
  night_reason    the typed explanation for the night difference
  was_day_diff    what the day difference was before this save (edits only)
  was_night_diff  the same for the night difference
  changed         which figures moved, and from what to what (edits only)
  cross_day_edit  an edit made on a later calendar date than the first save
  pending_day     the day's ledger had not been made when it was edited
  now_balances    this save cleared a difference the day used to carry
  filled_a_gap    the day after this one was already on record
  released_by     for a released row, the day whose entry released it

A BLANK NUMERIC CELL READS BACK AS `NaN`, which is the same convention the rest
of the program uses for "nobody supplied this" (DayInput.NOT_COUNTED). It is a
Float64, so the tuple type never has to widen, and it is never equal to
anything, so it cannot be mistaken for a real figure.
"""
const Row = NamedTuple{(:when, :who, :what, :day, :kind, :journal, :ledger,
                        :day_diff, :night_diff, :reason, :night_reason,
                        :was_day_diff, :was_night_diff, :changed,
                        :cross_day_edit, :pending_day, :now_balances,
                        :filled_a_gap, :released_by),
                       Tuple{DateTime, String, String, Date, String, String, String,
                             Float64, Float64, String, String,
                             Float64, Float64, String,
                             Bool, Bool, Bool, Bool, Union{Nothing,Date}}}

# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

"""
    after_save(outcome; rec, previous, before) -> Int

Append the rows describing one save, and return how many were written.

  outcome   what `process_day` returned. A refused save has `ok == false` and
            writes nothing at all: nothing was written to the books either, so
            there is nothing to record.
  rec       the day as it was saved.
  previous  the journal row this date held BEFORE this save, read by the caller
            before `process_day` touched it, or `nothing` if the date was not in
            the books. It is the only source of the "was" figures — once
            `upsert_day!` has run they no longer exist anywhere.
  before    the three facts about the books as they were before this save:
            `in_books`, `next_in_books`, `ledger_exists`. The caller has them
            already (`day_context` reads them once per request), so they are
            passed rather than looked up a second time — and, more importantly,
            looking them up NOW would give the wrong answer, because this save
            has already changed them.

ONE ROW PER FACT. The saved day gets a row, and so does each held ledger that
this save released, because a released day belongs to a different date, carries
its own difference, and nothing on the screen that saved it said so. Reporting
it as a line inside somebody else's row would make it unsearchable by the date
it is actually about.

THIS FUNCTION NEVER THROWS. See the module header: the day is already in the
books by the time it runs, and a paper trail that can refuse a save is a worse
bargain than no paper trail. A failure is one warning and a return of zero.
"""
function after_save(outcome; rec::DayRecord,
                    previous::Union{Nothing,DayRecord} = nothing,
                    before = nothing,
                    # `ctx` is the same three facts under the name `day_context`
                    # gives them. Accepted so that either spelling works at the
                    # call site and neither front door has to translate.
                    ctx = nothing)
    try
        outcome.ok || return 0

        facts = before === nothing ? ctx : before
        facts === nothing &&
            error("after_save was given no `before` facts, so the flags cannot be worked out.")

        who = get(ENV, "USERNAME", get(ENV, "USER", "unknown"))
        t   = now()
        edited = outcome.journal == "replaced"

        # THE ORDER HERE MATTERS: `first_seen` must be asked before this save's
        # own row is appended, or every edit would find itself and conclude it
        # was first saved today.
        #
        # A day with no history in the log counts as one saved before the log
        # existed, so its first edit is reported. That is the conservative way
        # round: the first week of reports may name a few old days, which is
        # noise, where the other way round would hide a real edit, which is the
        # thing this file was built for.
        cross = facts.in_books && (fs = first_seen(rec.date); fs === nothing || fs < Dates.today())

        # A ledger that has not been made yet means nobody has seen this day
        # posted, so an edit to it is worth reporting even on the day it was
        # first saved. A closed day is excluded because it never gets a ledger
        # and so would qualify forever.
        pending = facts.in_books && !facts.ledger_exists && !is_closed(rec)

        # The day after this one was already on record and this one was not:
        # somebody has just filled a hole, and the ledger that was waiting on it
        # can now be made.
        gap = facts.next_in_books && !facts.in_books

        was_dv = previous === nothing ? NaN : previous.amounts[:day_variance]
        was_ov = previous === nothing ? NaN : previous.amounts[:overnight_variance]

        # An unbalanced day edited until it balances. Worth its own flag because
        # the owner was told about the difference and would otherwise be left
        # believing it still stands.
        balances = previous !== nothing &&
                   _has_difference(was_dv, was_ov) &&
                   !_has_difference(outcome.day_variance, outcome.overnight_variance)

        rows = Row[]
        push!(rows, Row((t, who,
                         edited ? "edited" : "saved",
                         rec.date,
                         is_closed(rec) ? "closed" : "trading",
                         outcome.journal,
                         outcome.daily_ledger,
                         outcome.day_variance, outcome.overnight_variance,
                         outcome.reason, outcome.opening_reason,
                         was_dv, was_ov,
                         edited ? _changed_text(previous, rec) : "",
                         cross, pending, balances, gap,
                         nothing)))

        # A released day is always a trading day: a closed day needs no ledger
        # and is never held, so it can never be released.
        for r in outcome.released_days
            push!(rows, Row((t, who, "released", r.date, "trading",
                             "", "written",
                             r.day_variance, r.overnight_variance,
                             r.reason, r.opening_reason,
                             NaN, NaN, "",
                             false, false, false, false,
                             outcome.date)))
        end

        _append!(rows)
        return length(rows)
    catch e
        @warn "The change log could not be written. The day is still in the books." exception = e
        return 0
    end
end

"""
    _changed_text(previous, rec) -> String

Which figures moved, and from what to what — the one thing the books cannot say
after `upsert_day!` has run.

Walks the journal's numeric columns in the order they appear on the form, then
the two reasons, then the kind of day. THE VARIANCE COLUMNS ARE SKIPPED on
purpose: they are computed from the figures rather than typed, so naming them
here would report the same correction twice — once as the closing balance that
moved and again as the difference that moved with it. Their before-and-after
lives in its own pair of columns.

Two blanks count as no change; one blank counts as a change, because a figure
appearing where there was none is exactly the sort of edit worth seeing.
"""
function _changed_text(previous, rec::DayRecord)
    previous === nothing && return ""
    parts = String[]

    for k in JOURNAL_KEYS
        k in VARIANCE_KEYS && continue
        a = previous.amounts[k]
        b = rec.amounts[k]
        _same_money(a, b) && continue
        push!(parts, "$(label_of(k)) $(Checks.money(a)) -> $(Checks.money(b))")
    end

    # The reasons are quoted so that an empty one reads as `""` rather than as a
    # gap somebody might mistake for a formatting fault.
    if strip(previous.reason) != strip(rec.reason)
        push!(parts, "Reason \"$(previous.reason)\" -> \"$(rec.reason)\"")
    end
    if strip(previous.opening_reason) != strip(rec.opening_reason)
        push!(parts, "Night reason \"$(previous.opening_reason)\" -> \"$(rec.opening_reason)\"")
    end
    if previous.status != rec.status
        push!(parts, "Kind of day $(previous.status) -> $(rec.status)")
    end

    return join(parts, "; ")
end

"Two money figures that are the same as far as this program is concerned: both
blank, or within half a cent of each other (Checks.MONEY_TOL)."
_same_money(a::Float64, b::Float64) =
    (isnan(a) && isnan(b)) ? true :
    (isnan(a) || isnan(b)) ? false : abs(a - b) < Checks.MONEY_TOL

"Has this pair of variances a real difference in it? A blank is not a
difference, and neither is a figure below the smallest coin in circulation."
_has_difference(dv::Float64, ov::Float64) =
    (!isnan(dv) && !Checks.is_zero_money(dv)) || (!isnan(ov) && !Checks.is_zero_money(ov))

# ---------------------------------------------------------------------------
# The file
# ---------------------------------------------------------------------------

"Everything in a row as the text that lands in its cell. THE ONE PLACE the
programmer's field names and the owner's column headers meet, and the reason
the two lists can be checked against each other by eye."
_cells(r::Row) = String[_dt_text(r.when),
                        r.who,
                        r.what,
                        string(r.day),
                        r.kind,
                        r.journal,
                        r.ledger,
                        _num_text(r.day_diff),
                        _num_text(r.night_diff),
                        r.reason,
                        r.night_reason,
                        _num_text(r.was_day_diff),
                        _num_text(r.was_night_diff),
                        r.changed,
                        string(r.cross_day_edit),
                        string(r.pending_day),
                        string(r.now_balances),
                        string(r.filled_a_gap),
                        r.released_by === nothing ? "" : string(r.released_by)]

"Seconds, not minutes: two saves a minute apart are ordinary, and the report
prints the time of day from this."
_dt_text(t::DateTime) = Dates.format(t, "yyyy-mm-dd HH:MM:SS")

"A blank cell for a figure nobody supplied. Written plainly rather than as
`NaN`, which a spreadsheet shows as an error."
_num_text(x::Float64) = isnan(x) ? "" : string(x)

"""
    _frame(rows) -> DataFrame

The rows as a table of strings, one column per header.

EVERY COLUMN IS A STRING, going out as well as coming back. It costs nothing —
CSV is text either way — and it removes the one failure this file could
plausibly have: a column that happens to be blank on every row of one batch
being written or read as a different type from the same column in the batch
before it.
"""
function _frame(rows::Vector{Row})
    df = DataFrame([c => String[] for c in COLUMNS])
    for r in rows
        push!(df, _cells(r))
    end
    return df
end

"""
    _write(path, rows) -> Int

Append `rows` to one file, writing the header only when the file is new.

Split out from `_append!` so that `warmup_roundtrip` can exercise exactly this
code on a scratch file. The warm-up must compile the CSV writer without writing
a byte under the records folder, and the only way to be sure it compiles the
same writer is for there to be one.
"""
function _write(path::AbstractString, rows::Vector{Row})
    isempty(rows) && return 0
    mkpath(dirname(path))
    existed = isfile(path)
    CSV.write(path, _frame(rows); append = existed, header = !existed)
    return length(rows)
end

_append!(rows::Vector{Row}) = _write(Layout.change_log_path(), rows)

"""
    _rows_from(df) -> Vector{Row}

An already-read table back as rows.

A LINE THAT CANNOT BE READ IS SKIPPED, NOT THROWN. This file is appended to by
a program that must never fail a save, which means a half-written last line is
possible after a power cut; and it is a file a person may open and save from a
spreadsheet. Either way, one unreadable line must not cost the owner the whole
report. One warning is raised for the batch — twenty identical lines in a
terminal nobody is watching are no more informative than one.
"""
function _rows_from(df::DataFrame)
    out = Row[]
    have = Set(names(df))
    for c in COLUMNS
        if !(c in have)
            @warn "The change log does not have the column \"$c\", so it was not read." maxlog = 1
            return out
        end
    end
    warned = false
    for i in 1:nrow(df)
        try
            push!(out, _row_at(df, i))
        catch e
            if !warned
                @warn "A line of the change log could not be read and was skipped." exception = e
                warned = true
            end
        end
    end
    return out
end

function _row_at(df::DataFrame, i::Int)
    g(c) = _text(df[i, c])
    return Row((_dt(g("when")), g("who"), g("what"), _date(g("day")), g("day kind"),
                g("journal"), g("ledger"),
                _num(g("day difference")), _num(g("night difference")),
                g("reason"), g("night reason"),
                _num(g("was day difference")), _num(g("was night difference")),
                g("changed"),
                _bool(g("cross day edit")), _bool(g("pending day")),
                _bool(g("now balances")), _bool(g("filled a gap")),
                _maybe_date(g("released by"))))
end

# `missing` is what CSV.jl hands back for an empty cell. Every one of these is
# the inverse of the matching `_*_text` above.
_text(v) = (v === missing || v === nothing) ? "" : String(v)
_num(s::AbstractString)  = (t = strip(s); isempty(t) ? NaN : parse(Float64, t))
_bool(s::AbstractString) = lowercase(strip(s)) == "true"
_date(s::AbstractString) = Date(strip(s))
_dt(s::AbstractString)   = DateTime(strip(s), dateformat"yyyy-mm-dd HH:MM:SS")
_maybe_date(s::AbstractString) = (t = strip(s); isempty(t) ? nothing : Date(t))

"""
    _read_log() -> Vector{Row}

The whole log, oldest first. An absent file is an empty list rather than an
error: that is a records folder nothing has been saved into yet, which is a
perfectly ordinary state and the honest answer is "nothing has happened".
"""
function _read_log()
    p = Layout.change_log_path()
    isfile(p) || return Row[]
    df = try
        CSV.read(p, DataFrame; types = String, missingstring = "")
    catch e
        @warn "The change log could not be read, so this report may be incomplete." file = p exception = e
        return Row[]
    end
    return _rows_from(df)
end

# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

"""
    rows_between(from, to) -> Vector{Row}

Every row written after `from` and up to and including `to`, in the order they
were written. `from === nothing` means "from the beginning", which is what the
very first report asks for.

HALF-OPEN AT THE START, CLOSED AT THE END, so that consecutive reports tile the
timeline exactly: a row written at precisely 6:30:00 pm belongs to the report
that closes at 6:30 pm and not to the one that opens there. Without that rule a
save landing on the second would be reported twice or not at all, and the answer
would depend on which.
"""
function rows_between(from::Union{Nothing,DateTime}, to::DateTime)
    rows = _read_log()
    return filter(r -> r.when <= to && (from === nothing || r.when > from), rows)
end

"""
    first_seen(d) -> Date or nothing

The calendar date on which this business day first appeared in the log, or
`nothing` when it is not in the log at all.

WHAT IT IS FOR: the owner's rule is that figures may be corrected freely on the
day they were typed and that a correction made later is worth reporting. This is
the "day they were typed". It is read from the log rather than from the books
because the books do not carry it — that is the whole reason this file exists.

AN "edited" ROW COUNTS AS A FIRST SIGHTING. A day saved before this log existed
has no "saved" row anywhere, and its first appearance here is an edit; treating
that edit as the first sighting would then make every later edit look
same-day and silent. Counting it means such a day is reported once more than
strictly necessary, which is the right way to be wrong.
"""
function first_seen(d::Date)
    best = nothing
    for r in _read_log()
        r.day == d || continue
        (r.what == "saved" || r.what == "edited") || continue
        seen = Date(r.when)
        (best === nothing || seen < best) && (best = seen)
    end
    return best
end

"""
    warmup_roundtrip(path)

Write one made-up row to a scratch file and read it straight back, so that the
CSV writer, the CSV reader and every conversion in this module are compiled
before the first real save.

`path` IS NEVER UNDER THE RECORDS FOLDER. The server's warm-up leaves the books
byte-for-byte as it found them, and a test asserts it; the caller hands in a
temporary file and deletes it afterwards.
"""
function warmup_roundtrip(path::AbstractString)
    rm(path; force = true)
    sample = Row((now(), "warmup", "saved", Dates.today(), "trading",
                  "added", "written", 0.0, 0.0, "", "", NaN, NaN, "",
                  false, false, false, false, nothing))
    _write(path, Row[sample])
    _rows_from(CSV.read(path, DataFrame; types = String, missingstring = ""))
    return nothing
end

end # module Changes
