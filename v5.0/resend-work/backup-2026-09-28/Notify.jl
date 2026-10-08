module Notify

using Dates, TOML, Sockets
using ..Config
using ..Layout
using ..DayInput
using ..AuditLog
using ..Checks
using ..Chain
using ..Changes

# =============================================================================
# NOTIFY — one email a day, saying what happened in the books.
#
# WHAT THE OWNER ASKED FOR, IN ONE SENTENCE: to be told what happened each day
# without having to ask the people who typed it. Two things drive it. Days that
# do not balance already carry a typed reason, and the owner wants to read them.
# And there are a handful of things a keen user could let pass unnoticed — a
# day quietly edited a week after it was saved, a day edited while its ledger is
# still held, a day that did not balance until it was edited until it did.
#
# ONE REPORT A DAY, AT A FIXED TIME, AND NOTHING ELSE. An earlier version of this
# file sent a message the moment a day was saved. It was built, and it was
# reverted, and the reason is worth keeping written down: a message per event
# arrives while the person who caused it is still at the desk, says only what
# that one save did, and — because most saves are ordinary — teaches its reader
# to stop opening them. A single report at the end of the day arrives when the
# day is finished, puts every fact in one place in the order things happened,
# and is worth reading because it is the only one.
#
# A QUIET DAY STILL SENDS. "Nothing to report" is information: it says the
# program was running, the mailbox works, and nobody entered anything. Silence
# then means something is wrong, which is the whole point of sending at a fixed
# time. Without it, a server left switched off looks exactly like a quiet week.
#
# A MISSED REPORT IS NOT LOST. The cutoff the last report covered is written to
# a small file, so a server started the next morning notices it owes one and
# sends a single email covering the whole missed window. One email, not one per
# missed day: the owner wants to know what happened, not to be punished for
# having been closed.
#
# NOTHING HERE IS A RECORD. Every figure in the report is read back out of the
# change log and the journals; delete the Notifications folder and the books are
# untouched. The report is a reader of the paper trail, never a second copy of
# it (see Changes.jl, which is the trail itself).
#
# EMAIL IS OFF UNTIL SOMEBODY CONFIGURES IT. No notify.toml, no mailbox, no
# error, no folder created — `settings()` is `nothing` and every entry point
# says so and returns. That is the state a fresh copy of this program is in, and
# the state the tests run in. The change log is written either way.
#
# THE PASSWORD IS NEVER PRINTED, LOGGED OR PUT IN A FILE THIS PROGRAM WRITES. It
# exists in notify.toml, which is git-ignored, and in the options handed to the
# transport. `_scrub` takes it back out of any error text before that text
# reaches the console or the audit log.
#
# THE FORM KNOWS NOTHING ABOUT ANY OF THIS. No endpoint mentions email, no save
# is slower because of it, and no save can fail because of it. A send happens on
# a timer, after the form already has its answer.
# =============================================================================

export enabled, enqueue, flush!, build_digest, tick

"""
    TRANSPORT[]

How a message actually leaves the machine: `TRANSPORT[](to, subject, body)`,
throwing on failure.

A `Ref` rather than a plain function so the tests can put a capture function in
its place and never send anything. That indirection is also the only reason the
send path can be exercised at all — the alternative is a test that needs a
mailbox, an internet connection and somebody's password.
"""
const TRANSPORT = Ref{Function}()

"""
    LAST_FLUSH[]

When the outbox was last tried. Only the timer reads it, and only to stop a
machine with no internet from dialling out every sixty seconds for a week.
"""
const LAST_FLUSH = Ref(DateTime(0))

"The timer that does the work, while there is one."
const SCHEDULE = Ref{Union{Nothing,Timer}}(nothing)

"True until the timer has fired once. The first tick is the catch-up tick."
const FIRST_TICK = Ref(true)

"Whether SMTPClient has been loaded into this process yet. See `_load_smtp`."
const SMTP_LOADED = Ref(false)

# --- Settings ---------------------------------------------------------------

"When the report goes out if notify.toml does not say otherwise: half past six
in the evening, machine time. The clinic is in Guyana and so is the machine, so
there is no timezone to reason about and no daylight saving to cross."
const DEFAULT_SEND_AT = Time(18, 30)

"""
    settings() -> NamedTuple or nothing

The mailbox settings from `notify.toml`, or `nothing` when the file is absent or
unusable.

Re-read on each call rather than cached: the file is a few lines, the timer asks
once a minute, and a cached copy would mean editing the settings needed the
server restarted — which on this machine means the clinic's form closing
mid-morning.

A file that cannot be parsed, or that names no `to` address, is treated exactly
like no file at all, with one warning. Refusing to run because an email setting
is malformed would be the wrong trade every time.

`from` defaults to `user` rather than to `to`, because Gmail — and most other
providers — reject a message whose sender is not the mailbox that signed in. A
`from` copied from `to` looks helpful and produces a rejection nobody can read.
"""
function settings()
    p = Layout.notify_config_path()
    isfile(p) || return nothing
    cfg = try
        TOML.parsefile(p)
    catch e
        @warn "The email settings could not be read, so no report will be sent." file = p exception = e
        return nothing
    end
    to = String(get(cfg, "to", ""))
    isempty(strip(to)) && return nothing
    user = String(get(cfg, "user", ""))
    fallback_from = isempty(strip(user)) ? to : user
    return (to             = String(strip(to)),
            from           = String(strip(String(get(cfg, "from", fallback_from)))),
            smtp           = String(get(cfg, "smtp", "")),
            user           = user,
            password       = String(get(cfg, "password", "")),
            subject_prefix = String(get(cfg, "subject_prefix", "ldgr: ")),
            send_at        = _send_at(get(cfg, "send_at", "")))
end

"""
    _send_at(text) -> Time

The hour the report goes out, read from `"HH:MM"` on a 24-hour clock.

An unreadable value falls back to half past six with one warning rather than
refusing to send at all. The settings file is edited by hand by somebody who is
not a programmer; a typo in the time should cost them the time they chose, not
the report.
"""
function _send_at(v)
    s = strip(String(v))
    isempty(s) && return DEFAULT_SEND_AT
    t = tryparse(Time, s, dateformat"HH:MM")
    if t === nothing
        @warn "The email settings do not give a readable send time (\"HH:MM\"), " *
              "so the report will go out at 6:30 pm." maxlog = 1
        return DEFAULT_SEND_AT
    end
    return t
end

"True when there is a mailbox to send to."
enabled() = settings() !== nothing

"Where the report goes, for the line printed when the server starts."
function recipient()
    s = settings()
    return s === nothing ? "" : s.to
end

"The time of day the report goes out, written the way the report itself says it.
Used in the line the server prints when it starts."
function send_at_text()
    s = settings()
    return Dates.format(s === nothing ? DEFAULT_SEND_AT : s.send_at, "HH:MM")
end

"The subject prefix, with a sensible one when email is off — `build_digest`
is allowed to be called with no settings at all (the warm-up does exactly that)."
function _prefix()
    s = settings()
    return s === nothing ? "ldgr: " : s.subject_prefix
end

# --- Wording ----------------------------------------------------------------

"The way a date is written to a person: 3 September 2026."
_long(d::Date) = Dates.format(d, "d U yyyy")

"The same date without the year, for the covering line where the year has
already been said once."
_short(d::Date) = Dates.format(d, "d U")

"""
    _clock(t) -> String

A time of day the way a person says it: 6:30 pm, 10:12 am.

Written out by hand rather than with a format code because Julia's `p` is not
portable across versions and this string goes in front of somebody who is not
reading it twice.
"""
function _clock(t)
    h = Dates.hour(t)
    mi = Dates.minute(t)
    half = h < 12 ? "am" : "pm"
    h12 = h % 12
    h12 == 0 && (h12 = 12)
    return "$(h12):$(lpad(mi, 2, '0')) $(half)"
end

"shortage/surplus, in the words the whole program uses for a difference. The
sign convention is Checks.day_residual's: negative means money is missing."
_kind(v::Float64) = v < 0 ? "Shortage" : "Surplus"

"Is this a real difference? A blank is not one, and neither is a figure below
the smallest coin in circulation."
_real(v::Float64) = !isnan(v) && !Checks.is_zero_money(v)

"One difference, as money, always positive — the word in front of it says which
way it goes."
_amount(v::Float64) = Checks.money(abs(v))

_rule() = repeat("-", 69)

"Small counts read better as words in a sentence and as digits in a subject
line, which is why there are two spellings of the same number in this file."
const _WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight",
                "nine", "ten", "eleven", "twelve"]
_word(n::Integer) = (1 <= n <= length(_WORDS)) ? _WORDS[n] : string(n)

"`1 day` / `2 days`, for the subject line."
_count(n::Integer, one::AbstractString, many::AbstractString) = "$(n) $(n == 1 ? one : many)"

_capitalise(s::AbstractString) = isempty(s) ? String(s) : uppercase(s[1:1]) * s[2:end]

# --- The window -------------------------------------------------------------

"""
    latest_cutoff(t, at) -> DateTime

The most recent moment the report was due, at or before `t`.

This is the whole of the scheduling arithmetic. Ask it at any instant and it
names the cutoff that should have been covered by now; compare that with the
marker file and the answer to "do we owe a report?" falls out. Nothing is held
in memory, nothing counts elapsed minutes, and a server restarted at any hour of
the day or night reaches the same conclusion as one that has been up for a week.
"""
function latest_cutoff(t::DateTime, at::Time)
    cut = DateTime(Date(t), at)
    return cut <= t ? cut : cut - Day(1)
end

"""
    last_reported() -> DateTime or nothing

The cutoff the last report covered, or `nothing` when none has ever gone out.

`nothing` is not an error and not an empty file — it is a fresh installation, and
the honest first report covers everything in the log from the beginning.
"""
function last_reported()
    p = Layout.digest_marker_path()
    isfile(p) || return nothing
    text = try
        strip(read(p, String))
    catch e
        @warn "The record of the last report could not be read." file = p exception = e
        return nothing
    end
    t = tryparse(DateTime, String(text), dateformat"yyyy-mm-dd HH:MM:SS")
    t === nothing && @warn "The record of the last report does not make sense and was ignored." file = p
    return t
end

"""
    mark_reported!(cutoff)

Write down how far the report has got.

WRITTEN TO A TEMPORARY FILE AND MOVED INTO PLACE, so the marker is either the
old cutoff or the new one and never half a line. It is one line long, so the
window in which a crash could tear it is vanishingly small — and if it were ever
torn, the consequence is a repeated or a skipped report, which is exactly the
thing this file exists to prevent.

THE MARKER MOVES WHEN THE REPORT IS QUEUED, NOT WHEN IT IS SENT. A week with no
internet should still produce seven daily reports, each covering its own day,
waiting in the outbox; advancing only on a successful send would instead produce
one enormous report covering the whole week once the connection came back.
"""
function mark_reported!(cutoff::DateTime)
    p = Layout.digest_marker_path()
    mkpath(dirname(p))
    tmp = p * ".tmp"
    write(tmp, Dates.format(cutoff, "yyyy-mm-dd HH:MM:SS"))
    mv(tmp, p; force = true)
    return nothing
end

# --- The report -------------------------------------------------------------

"""
    build_digest(from, to) -> (subject, body)

The one daily report, as plain text, for everything that happened after `from`
and up to `to`. `from === nothing` covers everything there is.

READS, NEVER WRITES. It is safe to call at any time, from the warm-up as well as
from the timer, and calling it twice produces the same report twice rather than
two different halves of one.

THE FACTS COME FROM TWO PLACES AND ONLY TWO. What happened comes out of the
change log, which is the only thing that knows when. What is still outstanding
comes from a live look at the disk, because a ledger that is waiting is a
standing condition rather than an event — it has to be repeated in every report
until it clears, and an event log can only say when it started.

NO WARNING CODES. L2-A and L3-E are how the program talks to itself. The person
reading this is not looking anything up.
"""
function build_digest(from::Union{Nothing,DateTime}, to::DateTime)
    rows    = Changes.rows_between(from, to)
    waiting = Chain.waiting_ledgers()

    # A released day belongs under the day whose entry released it, not under
    # its own date: the story is "this gap was filled, and here is what that
    # let through". Everything else is grouped by the day it is about.
    released_by = Dict{Date,Vector{Changes.Row}}()
    for r in rows
        r.what == "released" || continue
        r.released_by === nothing && continue
        push!(get!(released_by, r.released_by, Changes.Row[]), r)
    end

    groups = Dict{Date,Vector{Changes.Row}}()
    for r in rows
        r.what == "released" && continue
        push!(get!(groups, r.day, Changes.Row[]), r)
    end

    entered = Date[]     # DAYS ENTERED
    gaps    = Date[]     # GAPS FILLED
    changed = Date[]     # CHANGES TO DAYS ALREADY SAVED

    for d in sort(collect(keys(groups)); rev = true)
        g = groups[d]
        if any(r -> r.what == "saved", g)
            # A gap fill is still a day entered, but the interesting thing about
            # it is the hole it closed and the ledger that came out, so it is
            # told once, in the section about that.
            if any(r -> r.filled_a_gap, g) || haskey(released_by, d)
                push!(gaps, d)
            else
                push!(entered, d)
            end
        elseif any(r -> r.cross_day_edit || r.pending_day, g)
            # An edit on the same calendar day the figures were first typed is
            # the owner's idea of an ordinary correction, and is deliberately
            # silent. What is reported is an edit made later, or one made to a
            # day whose ledger nobody has seen yet.
            push!(changed, d)
        end
    end

    # --- counting, for the subject line and the opening sentence ------------
    n_entered = length(entered) + length(gaps)
    n_changed = length(changed)
    n_waiting = length(waiting)
    n_diff = 0
    for d in vcat(entered, gaps)
        last = groups[d][end]
        _real(last.day_diff)   && (n_diff += 1)
        _real(last.night_diff) && (n_diff += 1)
    end
    for (_, rs) in released_by, r in rs
        _real(r.day_diff)   && (n_diff += 1)
        _real(r.night_diff) && (n_diff += 1)
    end

    quiet = n_entered == 0 && n_changed == 0 && n_waiting == 0
    span  = from !== nothing && Date(to) - Date(from) > Day(1)

    io = IOBuffer()
    println(io, "LDGR DAILY REPORT")
    println(io, "$(_long(Date(to))), $(_covering(from, to))")
    println(io, "Records folder: $(Layout.ROOT)")
    println(io)
    if span
        println(io, "This report is late: the program was not running at $(_clock(_send_time())) ",
                    "on the days in between.")
        println(io)
    end

    if quiet
        println(io, span ? "Nothing was entered or changed, and every recorded day has its ledger." :
                           "Nothing was entered or changed today, and every recorded day has its ledger.")
        println(io)
    else
        println(io, _headline(n_entered, n_changed, n_waiting))
        println(io)

        if !isempty(entered)
            _section(io, "DAYS ENTERED")
            for d in entered
                _entered_block(io, d, groups[d])
            end
        end

        if !isempty(changed)
            _section(io, "CHANGES TO DAYS ALREADY SAVED")
            for d in changed
                _changed_block(io, d, groups[d])
            end
        end

        if !isempty(gaps)
            _section(io, "GAPS FILLED, AND THE LEDGERS THEY RELEASED")
            for d in gaps
                _gap_block(io, d, groups[d], get(released_by, d, Changes.Row[]))
            end
        end

        if !isempty(waiting)
            _section(io, "LEDGERS STILL WAITING")
            for d in waiting
                _waiting_block(io, d)
            end
            println(io, "   These days are in the books. Only their ledgers are outstanding, and each")
            println(io, "   is made by itself as soon as the day before it is entered. This list")
            println(io, "   repeats in every report until it is empty.")
            println(io)
        end
    end

    println(io, _rule())
    println(io, "This report is sent once a day at $(_clock(_send_time())). If it does not arrive, either the")
    println(io, "program was not running or the email settings need attention.")

    subject = "$(_prefix())report for $(_window(from, to)) — $(_summary(n_entered, n_diff, n_changed, n_waiting))"
    return (subject, String(take!(io)))
end

"The configured send time, or the default when email is off — the report says
when the next one is due, and the warm-up builds a report with no settings."
function _send_time()
    s = settings()
    return s === nothing ? DEFAULT_SEND_AT : s.send_at
end

"""
    _covering(from, to) -> String

"covering 14 September 6:30 pm to 15 September 6:30 pm".

Spelled out in full rather than left implicit, because the one question a reader
asks of a report that arrives late, or twice, is which hours it is actually
about.
"""
function _covering(from::Union{Nothing,DateTime}, to::DateTime)
    from === nothing && return "covering everything up to $(_short(Date(to))) $(_clock(to))"
    return "covering $(_short(Date(from))) $(_clock(from)) to $(_short(Date(to))) $(_clock(to))"
end

"""
    _window(from, to) -> String

The dates the subject line names: "15 September 2026" for an ordinary day,
"12–15 September 2026" when a report is catching up, and
"30 September – 2 October 2026" when the catch-up crosses a month.
"""
function _window(from::Union{Nothing,DateTime}, to::DateTime)
    to_d = Date(to)
    (from === nothing || to_d - Date(from) <= Day(1)) && return _long(to_d)
    a, b = Date(from), to_d
    if year(a) != year(b)
        return "$(_long(a)) – $(_long(b))"
    elseif month(a) != month(b)
        return "$(Dates.format(a, "d U")) – $(_long(b))"
    else
        return "$(day(a))–$(_long(b))"
    end
end

"""
    _summary(entered, differences, changed, waiting) -> String

The part of the subject after the dash: at most three counts, in the order the
owner cares about them, and "nothing to report" when there are none.

CAPPED AT THREE because a subject line is read in a list, at a glance, and the
fourth count is always the one the body says better.
"""
function _summary(entered::Int, differences::Int, changed::Int, waiting::Int)
    parts = String[]
    entered     > 0 && push!(parts, _count(entered, "day entered", "days entered"))
    differences > 0 && push!(parts, _count(differences, "difference", "differences"))
    changed     > 0 && push!(parts, _count(changed, "day changed", "days changed"))
    waiting     > 0 && push!(parts, _count(waiting, "ledger waiting", "ledgers waiting"))
    isempty(parts) && return "nothing to report"
    return join(parts[1:min(3, length(parts))], ", ")
end

"The one sentence under the heading, so the report can be judged without
reading it."
function _headline(entered::Int, changed::Int, waiting::Int)
    parts = String[]
    entered > 0 && push!(parts, entered == 1 ? "one day was entered" :
                                "$(_word(entered)) days were entered")
    changed > 0 && push!(parts, changed == 1 ? "one earlier day was changed" :
                                "$(_word(changed)) earlier days were changed")
    waiting > 0 && push!(parts, waiting == 1 ? "one ledger is waiting" :
                                "$(_word(waiting)) ledgers are waiting")
    return _capitalise(join(parts, ", ")) * "."
end

function _section(io, title::AbstractString)
    println(io, _rule())
    println(io, title)
    println(io, _rule())
end

# --- The blocks -------------------------------------------------------------

"""
    _entered_block(io, day, rows)

One day under DAYS ENTERED.

The LAST row is the state: a day saved and then corrected in the same sitting
shows the figures it ended up with, not the ones it passed through. The FIRST
saved row is who entered it and when, because that is the question being
answered; if a later row changed it, that is said on its own line rather than
quietly replacing the entry time.
"""
function _entered_block(io, d::Date, rows::Vector{Changes.Row})
    latest  = rows[end]
    first_i = something(findfirst(r -> r.what == "saved", rows), firstindex(rows))
    entry   = rows[first_i]

    headline = latest.kind == "closed" ? "Off day." :
               (_real(latest.day_diff) || _real(latest.night_diff)) ? "does not balance." : "balanced."
    println(io, "$(_long(d)) — $(headline)")
    _difference_lines(io, "   ", d, latest)
    println(io, "   Entered by $(entry.who) at $(_clock(entry.when)).")
    if first_i != lastindex(rows)
        println(io, "   Changed again by $(latest.who) at $(_clock(latest.when)).")
    end
    println(io)
end

"""
    _difference_lines(io, pad, day, row)

Each difference on one day, in its own words, with the reason typed for it.

THE TWO DIFFERENCES ARE NEVER MERGED. They have different causes and different
people to ask: one arose while the clinic was trading, the other between last
night's close and this morning's open. The form asks for a reason for each, and
this prints each reason beside the difference it explains.

The overnight line names the balance it is being compared with, read live from
the books. When the day before is missing — which is possible for a day entered
into a gap — it says so by leaving the figure out rather than by working one
out: nothing in this program calculates a closing balance.
"""
function _difference_lines(io, pad::AbstractString, d::Date, r::Changes.Row)
    if _real(r.day_diff)
        println(io, pad, "$(_kind(r.day_diff)) of $(_amount(r.day_diff)) during the day.")
        _reason_line(io, pad * "   ", r.reason)
    end
    if _real(r.night_diff)
        word = r.night_diff < 0 ? "less" : "more"
        prior = Chain.prior_day(d)
        if prior === nothing
            println(io, pad, "The opening balance is $(_amount(r.night_diff)) $(word) than ",
                        "the day before closed with.")
        else
            println(io, pad, "The opening balance is $(_amount(r.night_diff)) $(word) than ",
                        "the $(Checks.money(prior.closing)) the day before closed with.")
        end
        _reason_line(io, pad * "   ", r.night_reason)
    end
end

"The typed explanation, tucked under the difference it explains. `pad` is the
exact indent, because the two places this is used sit at different depths."
function _reason_line(io, pad::AbstractString, reason::AbstractString)
    text = strip(reason)
    println(io, pad, "reason: ", isempty(text) ? "(none given)" : text)
end

"""
    _changed_block(io, day, rows)

One day under CHANGES TO DAYS ALREADY SAVED.

This is the section the whole exercise was built for. It says which day was
changed, when it was first saved, why the change is being reported at all, what
moved, and whether the change cleared a difference the owner had already been
told about.

"what moved" is the `changed` cell of the log, which is a list joined with
semicolons; it is split back out so each figure gets its own line. A reason
containing "; " would split with it, which costs a line break in a sentence
nobody is parsing.
"""
function _changed_block(io, d::Date, rows::Vector{Changes.Row})
    latest = rows[end]
    println(io, "$(_long(d)) was changed on $(_long(Date(latest.when))).")

    seen = Changes.first_seen(d)
    seen === nothing || println(io, "   It was first saved on $(_long(seen)).")
    any(r -> r.pending_day, rows) &&
        println(io, "   Its ledger had not been made yet — it was waiting on the day before it.")

    for part in split(latest.changed, "; ")
        isempty(strip(part)) && continue
        println(io, "   ", part)
    end

    if any(r -> r.now_balances, rows) && !(_real(latest.day_diff) || _real(latest.night_diff))
        _was_line(io, rows)
        println(io, "   It balances now.")
    else
        _difference_lines(io, "   ", d, latest)
    end

    println(io, "   Changed by $(latest.who) at $(_clock(latest.when)).")
    println(io)
end

"What the difference used to be, for a day that has just been made to balance.
Read from the `was` columns, because by now the books no longer hold it."
function _was_line(io, rows::Vector{Changes.Row})
    for r in rows
        r.now_balances || continue
        parts = String[]
        _real(r.was_day_diff)   && push!(parts, "$(lowercase(_kind(r.was_day_diff))) of " *
                                                "$(_amount(r.was_day_diff)) during the day")
        _real(r.was_night_diff) && push!(parts, "$(lowercase(_kind(r.was_night_diff))) of " *
                                                "$(_amount(r.was_night_diff)) overnight")
        isempty(parts) || println(io, "   It did not balance before: $(join(parts, ", ")).")
        return nothing
    end
    return nothing
end

"""
    _gap_block(io, day, rows, released)

One day under GAPS FILLED, and the ledgers its entry released.

A gap fill is the one case where entering a day changes what the program knows
about a DIFFERENT day. Until the hole was closed, the day after it could not be
compared with anything and its ledger was held; now it can be, and a difference
may have turned up that nobody could have seen when that day was typed. It is
nested under the day that released it because that is the only way the two facts
read as one story.
"""
function _gap_block(io, d::Date, rows::Vector{Changes.Row}, released::Vector{Changes.Row})
    latest  = rows[end]
    first_i = something(findfirst(r -> r.what == "saved", rows), firstindex(rows))
    entry   = rows[first_i]

    println(io, "$(_long(d)) was entered on $(_long(Date(entry.when))), filling a gap:")
    println(io, "$(_long(d + Day(1))) was already on record and waiting for it.")
    latest.kind == "closed" && println(io, "   It was an Off day.")
    _difference_lines(io, "   ", d, latest)
    println(io, "   Entered by $(entry.who) at $(_clock(entry.when)).")

    for r in sort(released; by = x -> x.day)
        println(io, "   The ledger for $(_long(r.day)) was made.")
        if _real(r.day_diff)
            println(io, "      $(_kind(r.day_diff)) of $(_amount(r.day_diff)) during that day.")
            _reason_line(io, "      ", r.reason)
        end
        if _real(r.night_diff)
            word  = r.night_diff < 0 ? "less" : "more"
            prior = Chain.prior_day(r.day)
            if prior === nothing
                println(io, "      Its opening balance is $(_amount(r.night_diff)) $(word) than")
                println(io, "      the day before it closed with.")
            else
                println(io, "      Its opening balance is $(_amount(r.night_diff)) $(word) than the")
                println(io, "      $(Checks.money(prior.closing)) that $(_long(prior.date)) closed with.")
            end
            _reason_line(io, "      ", r.night_reason)
        end
    end
    println(io)
end

"""
    _waiting_block(io, day)

One line of LEDGERS STILL WAITING, naming the day that is missing when there is
one.

THIS LIST IS THE POINT OF REPEATING THE REPORT EVERY DAY. A held ledger is
silent by nature — nothing errors, the form says the day was saved, QuickBooks
imports what it is given, and the gap only surfaces at month end with four weeks
to search. Naming it every morning until it clears is the whole defence.
"""
function _waiting_block(io, d::Date)
    if !Chain.on_record(d - Day(1))
        println(io, "$(_long(d)) — saved, but its ledger cannot be made until")
        println(io, "   $(_long(d - Day(1))) is entered.")
    else
        println(io, "$(_long(d)) — saved, but its ledger has not been made yet.")
        println(io, "   The day before it is already on record.")
    end
    println(io)
end

# --- The schedule -----------------------------------------------------------

"""
    tick(; force = false, at = now()) -> Symbol

One beat of the clock. Returns what it did: `:off`, `:sent`, `:queued`,
`:retried`, `:waiting` or `:idle`.

EVERYTHING IS RE-DERIVED, EVERY TIME, from three things that outlive the
process: notify.toml, the marker file and the clock. Nothing is remembered
between ticks and nothing counts elapsed minutes, so a server restarted at any
moment picks up exactly where the last one left off, and a server that has been
up for a month behaves identically to one started a minute ago.

  :off      no notify.toml. Nothing is written and no folder is created.
  :sent     a report was owed, built, queued, marked and sent.
  :queued   a report was owed and is on disk, but could not go out yet.
  :retried  nothing was owed, but something is still in the outbox and it has
            been half an hour since the last attempt.
  :waiting  something is in the outbox, but it is too soon to try again.
  :idle     nothing owed, nothing waiting. The ordinary answer, 1,439 times a day.

`force` makes the cutoff this very moment, which is how a test — and
`LDGR_DIGEST_NOW=1` — asks for a report without waiting for the evening.

THE ORDER INSIDE THE OWED BRANCH IS DELIBERATE: build, queue, mark, then send.
The report is on disk before anything touches the network, so the worst a failed
send can cost is a delay.
"""
function tick(; force::Bool = false, at::DateTime = Dates.now())
    cfg = settings()
    cfg === nothing && return :off

    marker = last_reported()
    due    = force ? at : latest_cutoff(at, cfg.send_at)

    if force || marker === nothing || marker < due
        subject, body = build_digest(marker, due)
        enqueue((to = cfg.to, subject = subject, body = body, day = Date(due)))
        mark_reported!(due)
        LAST_FLUSH[] = at
        sent, failed = flush!()
        return (failed == 0 && sent > 0) ? :sent : :queued
    end

    dir = Layout.outbox_dir()
    isdir(dir) || return :idle
    any(f -> endswith(f, ".txt"), readdir(dir)) || return :idle

    # A clinic whose internet is down should not have this program dialling out
    # every sixty seconds all week. Half an hour is often enough that a
    # connection coming back at lunchtime is noticed before the evening, and
    # seldom enough that nobody would see it in a log.
    if at - LAST_FLUSH[] >= Minute(30)
        LAST_FLUSH[] = at
        flush!()
        return :retried
    end
    return :waiting
end

"""
    start_schedule!()

Start the once-a-minute timer that produces the report. Called from `start()`
after the warm-up and before the server begins listening.

A TIMER RATHER THAN A CHECK INSIDE THE SAVE PATH. The report is about the day,
not about any one save, and the commonest evening of all is one where nothing is
saved after six o'clock. Hanging it off saves would mean the report went out
only when somebody happened to enter something.

FIVE SECONDS FOR THE FIRST BEAT, then every minute. The first beat is the
catch-up: a server started the morning after a day it was switched off owes a
report, and the owner should have it before they have finished making coffee.

THE CALLBACK CANNOT THROW. A timer whose callback throws is cancelled, silently,
and no report is ever sent again for the life of the process — which is exactly
the failure this whole design is meant to be unable to have.

`LDGR_NO_DIGEST=1` switches it off, which is what every test run sets so that a
suite cannot queue mail. `LDGR_DIGEST_NOW=1` makes the first beat force a report
out regardless of the hour, for a manual end-to-end check.
"""
function start_schedule!()
    get(ENV, "LDGR_NO_DIGEST", "") == "1" && return nothing
    SCHEDULE[] === nothing || return nothing
    SCHEDULE[] = Timer(5; interval = 60) do _
        try
            first = FIRST_TICK[]
            FIRST_TICK[] = false
            tick(; force = first && get(ENV, "LDGR_DIGEST_NOW", "") == "1")
        catch e
            @warn "The daily report could not be prepared." exception = e
        end
    end
    return nothing
end

"Stop the timer. Only the tests and a REPL session need this; a server that is
shutting down takes the timer with it."
function stop_schedule!()
    t = SCHEDULE[]
    t === nothing || close(t)
    SCHEDULE[] = nothing
    return nothing
end

# --- The queue --------------------------------------------------------------

"""
    enqueue(msg) -> path

Write one message to the outbox. `msg` is `(to, subject, body, day)`.

Small, local and synchronous. The report exists on disk before anything touches
the network, so the only way to lose one is to delete it.

The file is the message: a header block of To/Subject/Attempts, a blank line,
then the body. Plain text, so a message stuck in the outbox can be read, fixed
or forwarded by hand without this program.
"""
function enqueue(msg)
    mkpath(Layout.outbox_dir())
    t = now()
    path = Layout.outbox_path(Layout.notice_name(t, msg.day))
    n = 1
    while isfile(path)                     # two notices in the same second
        n += 1
        path = Layout.outbox_path(Layout.notice_name(t, msg.day, n))
    end
    open(path, "w") do io
        println(io, "To: ", msg.to)
        println(io, "Subject: ", msg.subject)
        println(io, "Attempts: 0")
        println(io)
        print(io, msg.body)
    end
    return path
end

"""
    _read_notice(path) -> (to, subject, attempts, body) or nothing

Read one queued message back. A file that is not in the expected shape is left
alone and reported rather than sent as nonsense or deleted.
"""
function _read_notice(path::AbstractString)
    text = try
        read(path, String)
    catch
        return nothing
    end
    lines = split(text, '\n')
    length(lines) >= 4 || return nothing
    startswith(lines[1], "To: ") || return nothing
    startswith(lines[2], "Subject: ") || return nothing
    startswith(lines[3], "Attempts: ") || return nothing
    attempts = something(tryparse(Int, strip(lines[3][11:end])), 0)
    body = join(lines[5:end], "\n")
    return (to = String(strip(lines[1][5:end])),
            subject = String(strip(lines[2][10:end])),
            attempts = attempts,
            body = String(body))
end

"Rewrite a message that could not be sent, with one more attempt against its name."
function _bump_attempts(path::AbstractString, n)
    lines = String[String(l) for l in split(read(path, String), '\n')]
    lines[3] = "Attempts: $(n.attempts + 1)"
    write(path, join(lines, "\n"))
    return nothing
end

"""
    flush!() -> (sent, failed)

Send everything in the outbox, oldest first.

THE MAIL SERVER IS ASKED WHETHER IT IS THERE BEFORE ANYTHING IS SENT. libcurl
does not yield to Julia's scheduler and SMTPClient 0.6.5 exposes no timeout, so
a send to a host that is unreachable holds this single-threaded process for as
long as the operating system takes to give up — minutes, on a machine whose
internet has simply been unplugged. A five-second connection attempt answers the
same question for the whole batch and costs nothing when the answer is yes.

A message that fails is left exactly where it is, with one more attempt counted
against it, and tried again later. One warning is raised, in plain words, for the
whole batch — the terminal is not watched, and twenty identical lines are no more
informative than one.
"""
function flush!()
    cfg = settings()
    cfg === nothing && return (0, 0)
    dir = Layout.outbox_dir()
    isdir(dir) || return (0, 0)

    files = sort([Layout.outbox_path(f) for f in readdir(dir) if endswith(f, ".txt")])
    isempty(files) && return (0, 0)

    session = AuditSession(Layout.audit_log_path())

    # ONLY THE REAL TRANSPORT IS GATED ON REACHABILITY. The check exists because
    # libcurl cannot be given a deadline; anything put in `TRANSPORT[]` in its
    # place — the tests' capture function, or a hand-written one — can return
    # whenever it likes, and refusing to call it because a mail server somewhere
    # is not answering would make the send path impossible to exercise.
    if TRANSPORT[] === _smtp_send && !_reachable(cfg.smtp)
        log_event(session, "email: the mail server could not be reached — the report is still waiting to go out"; echo = false)
        log_entry(session; header = "email")
        @warn "The owner could not be emailed just now. The report is waiting and will go out later."
        return (0, length(files))
    end

    sent = 0; failed = 0
    for f in files
        n = _read_notice(f)
        if n === nothing
            failed += 1
            log_event(session, "email: could not read the queued notice $(basename(f)) — left in the outbox"; echo=false)
            continue
        end
        try
            TRANSPORT[](n.to, n.subject, n.body)
            mkpath(Layout.sent_dir())
            mv(f, Layout.sent_path(basename(f)); force=true)
            sent += 1
            log_event(session, "email sent to $(n.to): $(n.subject)"; echo=false)
        catch e
            failed += 1
            try _bump_attempts(f, n) catch end
            log_event(session, "email NOT sent ($(n.attempts + 1) attempt(s)): $(n.subject) — " *
                               _scrub(sprint(showerror, e)); echo=false)
        end
    end
    isempty(session.events) || log_entry(session; header="email")
    failed > 0 &&
        @warn "The owner could not be emailed just now. The report is waiting and will go out later."
    return (sent, failed)
end

# --- The transport ----------------------------------------------------------

"""
    _reachable(smtp) -> Bool

Can this machine open a connection to the mail server within ten seconds?

ASKED WITH A PLAIN SOCKET rather than by starting a send, because a socket can
be given a deadline and a send cannot. The connection is opened and closed
without a word being spoken, which is exactly what is wanted: the question is
whether there is an internet connection and a server listening, not whether the
password is right. A wrong password is a different failure and is reported as
one, after an attempt that is known to be able to finish.

`false` when the address cannot be parsed, when nothing answers, or when five
seconds pass. Any of those means the same thing to the caller: leave the report
in the outbox and try later.
"""
function _reachable(smtp::AbstractString)
    host, port = _host_and_port(smtp)
    isempty(host) && return false

    # The attempt is made in a task so that it can be abandoned. The `catch`
    # inside it is what keeps a refused connection from surfacing later as an
    # unhandled task failure in a terminal nobody is watching.
    t = @async try
        Sockets.connect(host, port)
    catch
        nothing
    end

    deadline = time() + 10.0   # ten, not five: one first-ever probe from a REPL was seen to miss five while everything else about the connection was fine
    while !istaskdone(t) && time() < deadline
        sleep(0.1)
    end
    istaskdone(t) || return false           # abandoned; the task closes itself out

    sock = try
        fetch(t)
    catch
        nothing
    end
    sock === nothing && return false
    try close(sock) catch end
    return true
end

"""
    _host_and_port(smtp) -> (String, Int)

`smtps://smtp.gmail.com:465` pulled apart. A missing port is the one the scheme
implies: 465 for `smtps`, which is encrypted from the first byte, and 587 for
`smtp`, which starts in the clear and upgrades.
"""
function _host_and_port(smtp::AbstractString)
    s = String(smtp)
    scheme = "smtp"
    i = findfirst("://", s)
    if i !== nothing
        scheme = lowercase(s[1:first(i)-1])
        s = s[last(i)+1:end]
    end
    s = String(first(split(s, '/')))
    port = startswith(scheme, "smtps") ? 465 : 587
    j = findlast(':', s)
    if j !== nothing
        p = tryparse(Int, s[j+1:end])
        if p !== nothing
            return (String(strip(s[1:j-1])), p)
        end
    end
    return (String(strip(s)), port)
end

"""
    _load_smtp()

Bring SMTPClient into this module, the first time anything actually needs it.

NOT A TOP-LEVEL `using`, deliberately. Loading SMTPClient costs a second or two
of the server's start-up, and a copy of this program with no notify.toml will
never send anything, so that second is spent for nothing on every machine that
has not configured email. Worse, a fresh machine that has not installed the
package would fail to load main.jl at all — the bookkeeping would stop working
because of a feature nobody had switched on.

The message for a missing package says exactly what to type. The person reading
it is a clinic owner with a terminal open because something did not work.
"""
function _load_smtp()
    SMTP_LOADED[] && return nothing
    try
        @eval Notify using SMTPClient
        SMTP_LOADED[] = true
    catch
        error("Email is configured but the SMTPClient package is not installed. " *
              "In Julia run: using Pkg; Pkg.add(\"SMTPClient\")")
    end
    return nothing
end

"""
    preload()

Load the mail package now rather than at the moment the first report goes out.

Called from `start()` only when email is configured, so the second it costs is
spent while the server is already starting up and never while somebody is
waiting for a day to save.
"""
preload() = (_load_smtp(); nothing)

"""
    _scrub(text) -> String

Anything about to be printed or logged, with the mailbox password taken out of
it. libcurl's error strings do not normally carry it, but "normally" is not a
guarantee worth making about a password, and the audit log is a file that stays.
"""
function _scrub(text::AbstractString)
    cfg = settings()
    (cfg === nothing || isempty(cfg.password)) && return String(text)
    return replace(String(text), cfg.password => "********")
end

"An address as SMTP wants it: <someone@example.com>."
_addr(s::AbstractString) = startswith(s, "<") ? String(s) : "<" * String(strip(s)) * ">"

"""
    _smtp_send(to, subject, body)

The real transport: the clinic's own mailbox over SMTP, through SMTPClient.jl.
No third-party service holds the clinic's figures, and the only credential is an
app password in a file that is never committed.

CALLED THROUGH `invokelatest`, and it has to be. SMTPClient is loaded on the
first send, which happens while this very function is already running; methods
defined by that load belong to a newer world than the one this call was compiled
in, and Julia would refuse to dispatch to them. `invokelatest` says "use the
methods that exist now", which is precisely the situation.

Throws on failure, which is what `flush!` expects — the message then stays in the
outbox and goes out next time.
"""
function _smtp_send(to::AbstractString, subject::AbstractString, body::AbstractString)
    cfg = settings()
    cfg === nothing && error("No email settings; nothing was sent.")
    isempty(cfg.smtp) && error("The email settings name no SMTP server, so nothing was sent.")
    _load_smtp()
    smtp = getfield(Notify, :SMTPClient)

    opts = Base.invokelatest(smtp.SendOptions;
                             isSSL = startswith(lowercase(cfg.smtp), "smtps"),
                             username = cfg.user, passwd = cfg.password)
    msg = Base.invokelatest(smtp.get_body, [_addr(to)], _addr(cfg.from),
                            String(subject), String(body))
    Base.invokelatest(smtp.send, cfg.smtp, [_addr(to)], _addr(cfg.from), msg, opts)
    return nothing
end

TRANSPORT[] = _smtp_send

end # module Notify
