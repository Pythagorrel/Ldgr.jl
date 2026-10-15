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

export after_save, rows_between, rows_checked, first_seen, first_saved_at, Row, COLUMNS

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
  cross_day_edit  an edit made after the session of the day's first save had
                  ended: on a later calendar date, or after the send time that
                  followed the first save (`_session_over`; the column keeps
                  its first name)
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
  send_at   the daily report's send time, which ends a day's free-correction
            session if midnight has not ended it first (`_session_over`).
            Neither front door passes it: `Notify` registers its setting in
            `SEND_TIME` when it loads. `nothing` leaves midnight as the only
            end, which is what the tests that run on the real clock pass.
  at        the moment of the save; `nothing` means now. Only the tests pass
            it, to save at a fixed time.

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
                    ctx = nothing,
                    send_at::Union{Nothing,Time} = _registered_send_time(),
                    at::Union{Nothing,DateTime} = nothing)
    try
        outcome.ok || return 0

        facts = before === nothing ? ctx : before
        facts === nothing &&
            error("after_save was given no `before` facts, so the flags cannot be worked out.")

        who = get(ENV, "USERNAME", get(ENV, "USER", "unknown"))
        t   = at === nothing ? now() : at
        edited = outcome.journal == "replaced"

        # THE ORDER HERE MATTERS: `first_saved_at` must be asked before this
        # save's own row is appended, or every edit would find itself and
        # conclude it was first saved just now.
        #
        # A day with no history in the log counts as one saved before the log
        # existed, so its first edit is reported. That is the conservative way
        # round: the first week of reports may name a few old days, which is
        # noise, where the other way round would hide a real edit, which is the
        # thing this file was built for.
        cross = facts.in_books &&
                (fs = first_saved_at(rec.date); fs === nothing || _session_over(fs, t, send_at))

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
        push!(parts, "Kind of day $(kind_words(previous.status)) -> $(kind_words(rec.status))")
    end

    return join(parts, "; ")
end

"""
A kind of day as the form names it: "Work day" or "Off day". The log's `kind`
column keeps the stored words ("trading" / "closed"), but anything a person
reads — the `changed` cell included — uses these. A value that is neither stays
as it is.
"""
kind_words(v::AbstractString) = v == STATUS_TRADING ? "Work day" : v == STATUS_CLOSED ? "Off day" : String(v)

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
    existed = isfile(path) && !_blank(path)
    existed && _mend_tail!(path)
    CSV.write(path, _frame(rows); append = existed, header = !existed)
    return length(rows)
end

"""
    _mend_tail!(path)

Make sure the next row appended to the log starts on a line of its own.

A WRITE CUT SHORT — a power cut, a full disk, a hand edit — can leave the last
line unfinished, and the next save would be appended onto it: the two would read
back as one damaged line and this save would vanish from every report. So:

  * a last line cut inside a quoted cell (the file ends with a quoted cell
    still open, judged the way CSV.jl reads it — see `_ends_in_quote`) has its
    quote closed first, or the open quote would run on through the next row
    and make the whole file unreadable;
  * a last line with no newline gets one.

Either way the damaged line stays on its own, where the reader names it, and
this row is written whole on the next line.
"""
function _mend_tail!(path::AbstractString)
    bytes = read(path)
    if _ends_in_quote(bytes)
        open(io -> write(io, "\"\n"), path, "a")
    elseif isempty(bytes) || last(bytes) != UInt8('\n')
        open(io -> write(io, "\n"), path, "a")
    end
    return nothing
end

"""
    _ends_in_quote(bytes) -> Bool

Does the file end inside a quoted cell, as CSV.jl would read it? A `"` opens a
quoted cell at the start of a cell, AND AFTER ANY SPACES OR TABS THAT BEGIN IT:
CSV.jl, read with the options `_parse` uses, takes ` "a,b"` (and the same after a
tab, or after several spaces) as a quoted cell, so a line cut as
`..., "a reason, cut` is cut inside one and needs its quote closed. Inside a
quoted cell, `""` is a quote and a lone `"` closes it; spaces after the closing
quote, before the comma, are allowed (`"abc" ,x` reads as `abc` and `x`).
Anywhere else a `"` is an ordinary character — so a quote typed into the middle
of a cell by hand (`5" drawer`, or `ab "x,y"`, where something other than a space
comes first) is not mistaken for a cut. Walking the raw bytes is safe for UTF-8:
no byte of a multi-byte character is a quote, a comma, a space, a tab or a line
end.
"""
function _ends_in_quote(bytes::AbstractVector{UInt8})
    q = UInt8('"')
    sep(b) = b == UInt8(',') || b == UInt8('\n') || b == UInt8('\r')
    pad(b) = b == UInt8(' ') || b == UInt8('\t')
    # :start   nothing in the cell yet
    # :lead    only spaces or tabs so far (a quote here still opens a quoted cell)
    # :bare    an ordinary cell, in which a quote is just a character
    # :quoted  inside a quoted cell
    # :closing a quote just seen inside a quoted cell: `""`, or the end of it
    st = :start
    for b in bytes
        if st === :start || st === :lead
            st = b == q ? :quoted : sep(b) ? :start : pad(b) ? :lead : :bare
        elseif st === :bare
            sep(b) && (st = :start)
        elseif st === :quoted
            b == q && (st = :closing)
        else
            st = b == q ? :quoted : sep(b) ? :start : :bare
        end
    end
    return st === :quoted
end

"""
    _header_line() -> String

The heading line as the writer writes it (CSV.jl, from an empty table): the
nineteen names, comma-separated, no quotes, one line feed. Taken from the writer
itself so that it can never drift from what a fresh log begins with.
"""
_header_line() = sprint(io -> CSV.write(io, _frame(Row[])))

"""
Does this text, from a small file with its byte-order mark and trailing blanks
already off, hold no data? It does if it is empty, or if it is only the START OF
THE HEADING LINE with no line break inside it (`when,who,wha`).
"""
_no_data(t::AbstractString) =
    isempty(t) || (!occursin(r"[\r\n]", t) && startswith(_header_line(), t))

"""
A log that holds no data, so that it is written afresh, with its header: an
empty file; one holding nothing but blanks or the byte-order mark a spreadsheet
writes when a sheet is emptied — which is what a person emptying the file to
mend it may leave; or one holding only the START OF THE HEADING LINE, with no
line break inside it (`when,who,wha`): the very first write, cut short by a power
cut or a full disk. Appended to, such a file would put the first row under a
broken or missing heading, or have it taken for the heading itself, and nothing
would read again — every report would say the change log could not be read, for
good.

Only that is treated as empty. A heading damaged any other way (a wrong name, a
column missing, a second line) may sit above rows somebody wants, so it is left
alone, and the reader names it.
"""
function _blank(path::AbstractString)
    n = filesize(path)
    n == 0 && return true
    n <= ncodeunits(_header_line()) + 64 || return false
    return _no_data(rstrip(lstrip(read(path, String), '\ufeff')))
end

_append!(rows::Vector{Row}) = _write(Layout.change_log_path(), rows)

"""
    Skipped

A row of the log that could not be read: its row number (the first row under
the header is row 1) and, when that much of it survives, the moment it was
written. `when` is `nothing` when even that cell is unreadable, and such a row
could belong to any report.
"""
const Skipped = NamedTuple{(:row, :when), Tuple{Int, Union{Nothing,DateTime}}}

"""
    _rows_from(df) -> (rows, skipped, problem)

An already-read table back as rows, with the rows that could not be read and a
plain sentence when the table as a whole could not be read.

A LINE THAT CANNOT BE READ IS SKIPPED, NOT THROWN. This file is appended to by
a program that must never fail a save, which means a half-written last line is
possible after a power cut; and it is a file a person may open and save from a
spreadsheet. Either way, one unreadable line must not cost the owner the whole
report. One warning is raised in the terminal, once — the report reads this
file every minute, and a line repeated every minute in a terminal nobody is
watching is no more informative than one.

BUT A SKIPPED LINE IS NEVER SILENT. The warning goes to a terminal nobody
watches; `skipped` and `problem` go into the report, so a log that could not be
read can never come out the other end as "nothing to report" (see
`rows_checked`).
"""
function _rows_from(df::DataFrame)
    out = Row[]
    skipped = Skipped[]
    have = Set(names(df))
    for c in COLUMNS
        if !(c in have)
            @warn "The change log does not have the column \"$c\", so it was not read." maxlog = 1
            return (out, skipped, "The change log has no \"$c\" column, so none of it could be read.")
        end
    end
    # Columns beyond the nineteen appear only when some line has too many
    # cells — two rows run together on one line, because the first was cut
    # short with no newline before the second was appended. Such a line may
    # hold a LATER row than its own `when` says, so it is dated nowhere and
    # counts against every report until somebody mends the file.
    extra = [c for c in names(df) if !(c in COLUMNS)]
    for i in 1:nrow(df)
        try
            push!(out, _row_at(df, i))
        catch e
            joined = any(c -> !ismissing(df[i, c]), extra)
            push!(skipped, Skipped((i, joined ? nothing : _when_at(df, i))))
            @warn "A line of the change log could not be read and was skipped." exception = e maxlog = 1
        end
    end
    return (out, skipped, "")
end

"The moment an unreadable row was written, if that one cell can still be read."
function _when_at(df::DataFrame, i::Int)
    try
        return _dt(_text(df[i, "when"]))
    catch
        return nothing
    end
end

function _row_at(df::DataFrame, i::Int)
    g(c) = _text(df[i, c])
    # A released row is always written with the day that released it; one
    # without is a line cut short in its last cell.
    g("what") == "released" && isempty(strip(g("released by"))) &&
        throw(ArgumentError("a released row with no \"released by\" day"))
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
"""
A cell as text. Bytes that are not valid UTF-8 — a line saved from a spreadsheet
in the wrong encoding — become the replacement character, so that no reader of
the log (the report, the state file) is ever handed an invalid string.
"""
function _text(v)
    (v === missing || v === nothing) && return ""
    t = String(v)
    return isvalid(t) ? t : String(map(c -> isvalid(c) ? c : '\ufffd', t))
end
_num(s::AbstractString)  = (t = strip(s); isempty(t) ? NaN : parse(Float64, t))
"""
A flag is always written as the word true or false (`_cells`), so anything
else — a blank, or half a word — means the line was cut short or edited by
hand. Throwing makes `_rows_from` skip the row and `rows_checked` report it,
instead of reading a torn line as a day with no difference and no flags.
TRUE/FALSE, as a spreadsheet saves them, still read.
"""
function _bool(s::AbstractString)
    t = lowercase(strip(s))
    t == "true"  && return true
    t == "false" && return false
    throw(ArgumentError("expected true or false, found $(repr(s))"))
end
# Julia's own parsers accept a date cut short ("2026-09-2" reads as 2
# September, "2026" as 1 January), which would date a torn line in some other
# report's stretch. So the full shape is required first.
const _DATE_SHAPE = r"^\d{4}-\d{2}-\d{2}$"
const _DT_SHAPE   = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
function _date(s::AbstractString)
    t = strip(s)
    occursin(_DATE_SHAPE, t) || throw(ArgumentError("expected a date as yyyy-mm-dd, found $(repr(s))"))
    return Date(t)
end
function _dt(s::AbstractString)
    t = strip(s)
    occursin(_DT_SHAPE, t) || throw(ArgumentError("expected yyyy-mm-dd HH:MM:SS, found $(repr(s))"))
    return DateTime(t, dateformat"yyyy-mm-dd HH:MM:SS")
end
_maybe_date(s::AbstractString) = (t = strip(s); isempty(t) ? nothing : _date(t))

"""
    _read_log_checked() -> (rows, skipped, problem)

The whole log, oldest first, with what could not be read of it.

An absent file is an empty list and no problem: that is a records folder
nothing has been saved into yet, which is a perfectly ordinary state and the
honest answer is "nothing has happened". A file that is there but cannot be
opened or parsed is the opposite — an empty list AND a problem — because the
honest answer then is "something may have happened and this program cannot
say what".
"""
function _read_log_checked()
    p = Layout.change_log_path()
    isfile(p) || return (Row[], Skipped[], "")
    bytes = try
        read(p)
    catch e
        @warn "The change log could not be opened, so this report may be incomplete." file = p exception = e maxlog = 1
        return (Row[], Skipped[], "The change log could not be opened ($(_brief(e))).")
    end
    df = try
        _parse(bytes)
    catch e
        @warn "The change log could not be read, so this report may be incomplete." file = p exception = e maxlog = 1
        return (Row[], Skipped[], "A line of the change log is damaged (for example a quotation mark " *
                                  "that is never closed), so none of it could be read.")
    end
    return _rows_from(df)
end

"""
    _parse(bytes) -> DataFrame

The log's bytes as a table of text. Every option here closes a way a damaged
line used to cost more than itself:

  * THE BYTES, NOT THE PATH. Given a path, CSV.jl maps the file into memory and
    on Windows lets go of it only when parsing succeeds; after a failure the
    file stayed locked until a chance garbage collection, and a mended copy
    could not be saved over it while ldgr ran.
  * THE DELIMITER IS FIXED. Left to guess, CSV.jl looks at the first few lines,
    and one damaged line among them can make it choose the colon of the clock
    times, so that nothing reads at all.
  * A TYPE FOR EACH NAMED COLUMN, not one type for all. A line with too many
    cells makes CSV.jl add columns part-way through; given one type for every
    column it sizes the new ones from its first guess at the row count and
    writes past their end — reading back garbage, or bringing the process
    down. Named types leave the extra columns to CSV.jl's own sizing.
  * `validate = false`, so a log missing one of the named columns still reads
    and is reported as such (`_rows_from`) rather than throwing here.
  * CSV.jl's warnings about short and long lines are silenced: the report reads
    the log every minute and says what is wrong in the report itself.
"""
_parse(bytes::Vector{UInt8}) =
    CSV.read(bytes, DataFrame; types = Dict(c => String for c in COLUMNS), validate = false,
             delim = ',', missingstring = "", silencewarnings = true)

"""
    _read_log() -> Vector{Row}

The whole log, oldest first, for the callers that only need the rows that could
be read (`rows_between`, `first_seen`). Unchanged in behaviour: what could not
be read is warned about and left out.
"""
_read_log() = first(_read_log_checked())

"""
The first line of an error, cut short. It goes into a report the owner reads,
where the whole of a parser's complaint would be noise.
"""
function _brief(e)
    text = strip(first(split(sprint(showerror, e), '\n')))
    return length(text) > 160 ? first(text, 157) * "..." : String(text)
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
timeline exactly: a row written at precisely 5:30:00 pm belongs to the report
that closes at 5:30 pm and not to the one that opens there. Without that rule a
save landing on the second would be reported twice or not at all, and the answer
would depend on which.
"""
function rows_between(from::Union{Nothing,DateTime}, to::DateTime)
    rows = _read_log()
    return filter(r -> _inside(r.when, from, to), rows)
end

"After `from` (or from the beginning) and up to and including `to`."
_inside(t::DateTime, from::Union{Nothing,DateTime}, to::DateTime) =
    t <= to && (from === nothing || t > from)

"""
    rows_checked(from, to) -> (rows, problem)

`rows_between`, and a plain sentence saying what could not be read, or `""`
when everything could.

THIS IS WHAT THE DAILY REPORT READS, and the reason it exists is that the
report must never give a false all-clear. `rows_between` answers an unreadable
log with an empty list, which is indistinguishable from a quiet day — and a
quiet day is exactly what the report would then say. With a problem in hand the
report says the log could not be read instead.

A SKIPPED ROW COUNTS AGAINST THIS WINDOW ONLY IF IT COULD BELONG TO IT: when its
`when` cell can still be read and falls outside the window, it is some other
report's business, and flagging it here would make one torn line from a power
cut shout in every report for the rest of time. A row whose `when` cannot be
read could belong to any window, so it counts against all of them until
somebody mends the file — and so does a line holding two rows run together,
whose second row could be from any later day (see `_rows_from`).
"""
function rows_checked(from::Union{Nothing,DateTime}, to::DateTime)
    rows, skipped, problem = _read_log_checked()
    inside = filter(r -> _inside(r.when, from, to), rows)
    isempty(problem) || return (inside, problem)
    bad = filter(s -> s.when === nothing || _inside(s.when, from, to), skipped)
    isempty(bad) && return (inside, "")
    # Counted as a person opening the file counts: the heading is line 1.
    problem = length(bad) == 1 ?
        "Line $(bad[1].row + 1) of Change Log.csv (counting the heading as line 1) could not be " *
        "read and was left out." :
        "$(length(bad)) lines of Change Log.csv could not be read and were left out (the first " *
        "is line $(bad[1].row + 1), counting the heading as line 1)."
    return (inside, problem)
end

"""
    first_saved_at(d) -> DateTime or nothing

The moment this business day first appeared in the log, or `nothing` when it is
not in the log at all.

WHAT IT IS FOR: the owner's rule is that figures may be corrected freely while
the day is still being counted and that a correction made later is worth
reporting (`_session_over`). This is the moment they were typed. It is read from
the log rather than from the books because the books do not carry it — that is
the whole reason this file exists.

AN "edited" ROW COUNTS AS A FIRST SIGHTING. A day saved before this log existed
has no "saved" row anywhere, and its first appearance here is an edit; treating
that edit as the first sighting would then make every later edit look
same-session and silent. Counting it means such a day is reported once more than
strictly necessary, which is the right way to be wrong.
"""
function first_saved_at(d::Date)
    best = nothing
    for r in _read_log()
        r.day == d || continue
        (r.what == "saved" || r.what == "edited") || continue
        (best === nothing || r.when < best) && (best = r.when)
    end
    return best
end

"""
    first_seen(d) -> Date or nothing

The calendar date of `first_saved_at(d)`: the date the report gives as the one
a day was first saved on.
"""
first_seen(d::Date) = (t = first_saved_at(d)) === nothing ? nothing : Date(t)

"""
    _session_over(first, t, send_at) -> Bool

Whether an edit made at `t` came after the session in which the day was first
saved (at `first`) had ended — that is, whether the owner's rules report it.

A SESSION ENDS AT MIDNIGHT OR AT THE SEND TIME, WHICHEVER COMES FIRST. Staff may
correct a day freely while they are still counting it. An edit on a later date
is reported, because revisiting a day whose cash was already counted is worth
the owner's eye. So is an edit made after the send time that followed the first
save: by then the owner has been emailed the old figures, and a correction left
out would leave them believing figures that no longer stand. A shortage put
right at 6 pm, after the 5:30 pm report, was the case that showed it. The send
time alone would not do: a day typed after it and changed the next morning
would then fall in one session, and a next-morning edit is exactly the kind the
owner wants to see.

TO THE SECOND, like the reports. The log stamps rows to the second and a row at
5:30:00 belongs to the 5:30 pm report, so an edit stamped 5:30:00 is in the same
report as a first save before it, and free. `send_at = nothing` leaves midnight
as the only end.
"""
function _session_over(first::DateTime, t::DateTime, send_at::Union{Nothing,Time})
    t = floor(t, Second)
    Date(t) > Date(first) && return true
    send_at === nothing && return false
    cut = DateTime(Date(first), send_at)
    return first <= cut < t
end

"""
    SEND_TIME

Where the change log gets the daily report's send time: a function of no
arguments that returns a `Time`, or `nothing` while none is set. `Notify` sets
it when it loads, because the send time is its setting (`notify.toml`) and it is
loaded after this module; the server and the command line both load it, so
neither passes the send time to `after_save` itself.
"""
const SEND_TIME = Ref{Any}(nothing)

"The send time `SEND_TIME` gives, or `nothing` if none is set or asking fails —
then only midnight ends a session. Never throws: it runs as `after_save`'s
default, before that function's own `try`."
function _registered_send_time()
    f = SEND_TIME[]
    f === nothing && return nothing
    try
        t = f()
        return t isa Time ? t : nothing
    catch
        return nothing
    end
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
    _rows_from(_parse(read(path)))
    return nothing
end

end # module Changes
