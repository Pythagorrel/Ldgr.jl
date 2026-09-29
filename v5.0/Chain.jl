module Chain

using Dates, DataFrames
using ..Config
using ..Layout
using ..DayInput
using ..Journal

# =============================================================================
# CHAIN — the one place a day is allowed to look at another day.
#
# ENTIRELY NEW IN v4.0.
#
# THE MODEL IT SERVES. Every day is a monolith: all of its arithmetic uses the
# figures typed for that day and nothing else. The single exception is the
# opening balance, which has to be compared against the previous day's closing —
# and that comparison is the whole of this module's job.
#
# WHY THE BLAST RADIUS IS TWO DAYS, AND WHY THAT IS PROVABLE. Every closing
# balance is a physical count, not a calculation. So a correction cannot travel
# through one:
#
#   * correcting any posting figure changes that day's day-variance only        (1 day)
#   * correcting an OPENING balance changes that day's day-variance and that
#     day's overnight-variance — both belong to the same day                    (1 day)
#   * correcting a CLOSING balance changes that day's day-variance and the NEXT
#     working day's overnight-variance                                          (2 days)
#
# and it stops there, because the next day's own closing balance was counted and
# did not move. Pairwise checks compose: if every adjacent pair agrees, the whole
# chain is consistent, and no full-month recomputation is ever needed. See
# "How Corrections Work in ldgr" for the worked examples.
#
# CLOSED DAYS ARE TRANSPARENT. A closed day carries the balance through
# untouched, so `prior_record` skips nothing and needs no special case: a closed
# day is a real journal row whose closing equals its opening. That is exactly
# why closed days are stored as rows rather than as absences — the chain stays
# literally continuous in the file, and a forgotten Wednesday cannot look like a
# Sunday.
#
# THIS MODULE HAS NO CALENDAR AND NO IDEA WHICH DAYS SHOULD EXIST. It never
# asserts that a day is missing. It answers one question — "is there a record
# before this date, and what did it close at?" — and lets the caller decide.
# =============================================================================

export prior_record, prior_day, is_genesis_date, ledger_ready, pending_ledgers,
       waiting_ledgers, month_chain_check, on_record, saved_record

"How many month-files to search backwards before giving up. A year of closure is
not a scenario worth supporting, and an unbounded loop over missing folders would
walk to the beginning of time on a fresh install."
const MAX_LOOKBACK_MONTHS = 12

"""
    _prev_month(y, m) -> (y, m)

December rolls the year back. Written out rather than using Dates arithmetic so
the year-boundary case is visible at the call site.
"""
_prev_month(y::Int, m::Int) = m == 1 ? (y - 1, 12) : (y, m - 1)

"""
    _latest_before(df, d) -> (date, closing) or nothing

The newest row in one journal strictly earlier than `d`.

`strictly earlier` matters: re-entering a day must compare against the day
BEFORE it, not against the copy of itself already sitting in the journal.
Without the `<` this would silently compare a day to itself and always pass.
"""
function _latest_before(df::DataFrame, d::Date)
    nrow(df) == 0 && return nothing
    best = nothing
    for i in 1:nrow(df)
        di = df[i, DATE_COL]
        if di < d && (best === nothing || di > df[best, DATE_COL])
            best = i
        end
    end
    best === nothing && return nothing

    col = colname_of(:closing_balance)
    # A journal written by v3.0 has no closing-balance column at all. conform!
    # backfills it with zeros, which would be a lie — v3.0 never recorded one.
    # Return `nothing` so the caller treats it as "no usable prior day" rather
    # than asserting the drawer closed at zero.
    col in names(df) || return nothing
    c = df[best, col]
    (ismissing(c) || isnan(c)) && return nothing

    return (date = df[best, DATE_COL], closing = Float64(c))
end

"""
    prior_record(d) -> (date=..., closing=...) or nothing

The most recent day on record before `d`, wherever it lives.

Searches this date's month file first, then walks backwards a month at a time.
That backward walk is what makes the 1st of a month, and the 1st of January,
ordinary days rather than special cases — the previous record simply happens to
be in another folder, and Layout already knows how to name it.
"""
function prior_record(d::Date)
    y, m = year(d), month(d)

    for _ in 1:MAX_LOOKBACK_MONTHS
        p = journal_path(y, m)
        if isfile(p)
            hit = _latest_before(read_journal(p), d)
            hit === nothing || return hit
        end
        y, m = _prev_month(y, m)
    end
    return nothing
end

"""
    prior_day(d) -> (date=..., closing=...) or nothing

The record for EXACTLY the previous calendar day, or nothing.

WHY CONTIGUITY RATHER THAN "WHATEVER CAME LAST". This is the rule the whole
missing-day defence rests on, and the alternative is actively dangerous.

Because a closed day is stored as a real row, EVERY calendar date between the
first entry and the last has a row — trading or closed. So a gap in the dates
is not an ambiguity about whether the clinic opened; it is a day somebody forgot
to enter.

If this chained to the latest earlier record instead, a forgotten Wednesday
would make Thursday's opening balance get compared against TUESDAY's closing.
The difference would then be Wednesday's entire net movement, and it would post
to Cash Over/Short as a single large overnight variance — a real day's trading
silently relabelled as unexplained cash. The books would balance and be wrong.

Requiring d − 1 means the program cannot make that mistake: with no Wednesday it
declines to compute the comparison at all and holds the ledger instead. Note
that this still involves no calendar and no notion of which days SHOULD exist —
it only asks whether the date immediately before this one has a row.
"""
function prior_day(d::Date)
    p = prior_record(d)
    p === nothing && return nothing
    return p.date == d - Day(1) ? p : nothing
end

"""
    _month_dates(d) -> Vector{Date}

Every date with a row in the journal for `d`'s month, or an empty list when that
month has no journal yet.
"""
function _month_dates(d::Date)
    p = journal_path(year(d), month(d))
    isfile(p) || return Date[]
    return read_journal(p)[!, DATE_COL]
end

"""
    on_record(d) -> Bool
    on_record(d, e) -> (Bool, Bool)

Does this date already have a journal row?

DIFFERENT QUESTION FROM `prior_record`, AND BOTH ARE NEEDED. `prior_record` asks
what came BEFORE a date; this asks whether the date itself is in the books. The
callers use it for two things: a day already in the books is not asked again to
authorise itself as the first day on record, and a day whose FOLLOWING date is
already in the books is filling a gap under it (Warnings Guide L3-E).

The two-date form answers both in one pass when they share a month, which the
day-and-the-day-after case almost always does. It exists so that a request does
not read the same file twice.
"""
on_record(d::Date) = d in _month_dates(d)

function on_record(d::Date, e::Date)
    ds = _month_dates(d)
    (year(e), month(e)) == (year(d), month(d)) && return (d in ds, e in ds)
    return (d in ds, on_record(e))
end

"""
    is_genesis_date(d) -> Bool

True when there is no record anywhere before `d`.

Distinguished from an ordinary gap because the two need opposite handling: a gap
holds the ledger until the missing day arrives, whereas the first day ever has
nothing to wait for and would be held forever. The chain has to start somewhere,
and that start is an explicit, audited decision rather than a silent default.
"""
is_genesis_date(d::Date) = prior_record(d) === nothing

"""
    ledger_ready(rec) -> (ready::Bool, prior, genesis::Bool)

Whether this day's ledger can be generated yet.

THIS IS THE GATE, AND IT IS ARITHMETIC RATHER THAN POLICY. The overnight
variance posts to the LATER day, so the Cash Over/Short row for the boundary
between yesterday and today is part of TODAY's ledger. With no previous day that
row is not computable, so the ledger is genuinely incomplete — it is not being
withheld out of caution. That distinction matters because it is not something a
future maintainer can reasonably argue their way around.

The gate depends on the previous day having a JOURNAL ROW, not a ledger. So a
hole blocks exactly the day after it; every later day sees its own predecessor
present and posts normally.

A closed day is always ready: it has no variances and generates no ledger.
"""
function ledger_ready(rec::DayRecord)
    is_closed(rec) && return (true, prior_day(rec.date), false)
    prior = prior_day(rec.date)          # contiguous — see prior_day for why
    prior === nothing && return (false, nothing, is_genesis_date(rec.date))
    return (true, prior, false)
end

# ---------------------------------------------------------------------------
# Reading a day back out of the books
# ---------------------------------------------------------------------------

"""
    saved_record(d) -> DayRecord or nothing

The day already in the books for `d`, read back from its month's journal, or
`nothing` when that date has not been saved.

MOVED HERE FROM server.jl, where it sat beside the endpoints although it is the
same job this module already does for main.jl's held-day retry: turn a journal
row back into a day. The copies had begun to matter — the change log needs the
figures a save is about to replace, and a second spelling of "read the row back"
is a second chance for the two to disagree about a blank drawer count or a
missing reason column. One copy, three callers.

Read-only, like everything else here.
"""
function saved_record(d::Date)
    p = journal_path(year(d), month(d))
    isfile(p) || return nothing
    return _record_from(read_journal(p), d)
end

"One row of an already-read journal as a DayRecord, or nothing when it has no
row for that date. The single place a journal row becomes a day again — callers
that have the month in hand already use this and do not read the file twice."
function _record_from(df::DataFrame, d::Date)
    i = findfirst(==(d), df[!, DATE_COL])
    i === nothing && return nothing
    return DayRecord(d,
                     Dict{Symbol,Float64}(k => Float64(df[i, colname_of(k)]) for k in JOURNAL_KEYS),
                     String(df[i, STATUS_COL]),
                     String(df[i, REASON_COL]),
                     String(df[i, OPENING_REASON_COL]))
end

"""
    pending_ledgers(y, m) -> Vector{Date}

Days recorded in this month's journal that still have no daily ledger file.

Recomputed by looking at the disk rather than tracked in a status file, for the
same reason the monthly ledger is rebuilt every run: a derived fact stored
separately is a second source of truth, and it will eventually disagree with
the first.

The caller surfaces this list in the daily report EVERY day until it empties.
Without that the gate would trade a noisy failure for a silent one — days would
sit un-posted indefinitely, QuickBooks would import cleanly the whole time, and
the problem would surface at month end as a mismatch with four weeks to search.
Closed days are excluded: they are complete without a ledger.
"""
function pending_ledgers(y::Integer, m::Integer)
    p = journal_path(y, m)
    isfile(p) && return _pending_from(read_journal(p))
    return Date[]
end

function _pending_from(df::DataFrame)
    out = Date[]
    has_status = STATUS_COL in names(df)
    for i in 1:nrow(df)
        d = df[i, DATE_COL]
        if has_status && String(df[i, STATUS_COL]) == STATUS_CLOSED
            continue
        end
        isfile(daily_ledger_path(d)) || push!(out, d)
    end
    return sort(out)
end

"""
    waiting_ledgers() -> Vector{Date}

Every day in the books, in any month, whose daily ledger has still not been
made. `pending_ledgers` asked of the whole records folder instead of one month.

READ FROM DISK EVERY TIME, NEVER STORED, for exactly the reason `pending_ledgers`
gives: a derived fact kept in a status file is a second source of truth, and it
will eventually disagree with the first. The cost is one journal read per month
that has ever been written, which is a handful of small files.

The months come from `Layout.recorded_months()` rather than from a date range,
so a gap year, a records folder restored from a backup and a fresh install all
answer correctly without this function owning a calendar.

The caller repeats this list in the daily report EVERY day until it empties. A
held ledger is silent by nature — nothing errors and QuickBooks imports cleanly
— so saying it out loud, daily, is the whole defence.
"""
function waiting_ledgers()
    out = Date[]
    for (y, m) in Layout.recorded_months()
        append!(out, pending_ledgers(y, m))
    end
    return sort!(unique!(out))
end

"""
    month_chain_check(y, m) -> NamedTuple

The month-level form of the daily identity (Warnings Guide §5):

    Σ(cash in − cash out) + Σ(variances) == closing(last day) − opening(first day)

Holds by construction when every day balanced and no day is missing, so it is
worth almost nothing as a check of arithmetic and a great deal as a check of
COVERAGE. It catches a day that was edited without its neighbour being
re-checked, a day whose ledger never posted, and a month that has been tampered
with outside the program.

Returns `ok=false` with `note` set when the month is empty or predates v4.0 and
has no balances to check.
"""
function month_chain_check(y::Integer, m::Integer)
    p = journal_path(y, m)
    isfile(p) || return (ok=false, note="no journal for this month", movement=0.0, span=0.0, diff=0.0)

    df = read_journal(p)
    nrow(df) == 0 && return (ok=false, note="journal is empty", movement=0.0, span=0.0, diff=0.0)

    ocol, ccol = colname_of(:opening_balance), colname_of(:closing_balance)
    (ocol in names(df) && ccol in names(df)) ||
        return (ok=false, note="journal predates the cash book", movement=0.0, span=0.0, diff=0.0)

    sort!(df, Symbol(DATE_COL))
    first_open = df[1, ocol]
    last_close = df[end, ccol]
    (isnan(first_open) || isnan(last_close)) &&
        return (ok=false, note="month has uncounted balances", movement=0.0, span=0.0, diff=0.0)

    colsum(k) = colname_of(k) in names(df) ? sum(skipmissing(df[!, colname_of(k)])) : 0.0

    inflow   = sum(colsum(k) for k in IDENTITY_INFLOW_KEYS;  init=0.0)
    outflow  = sum(colsum(k) for k in IDENTITY_OUTFLOW_KEYS; init=0.0)
    variance = sum(colsum(k) for k in VARIANCE_KEYS;         init=0.0)

    movement = inflow - outflow + variance     # what the books say the drawer moved
    span     = last_close - first_open         # what the counts say it moved

    return (ok = abs(movement - span) < 0.005,
            note = "",
            movement = movement,
            span = span,
            diff = span - movement)
end

end # module Chain
