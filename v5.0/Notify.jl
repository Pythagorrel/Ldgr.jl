module Notify

using Dates, TOML, SHA
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
# program was used, the mailbox works, and nobody entered anything. Silence then
# means something is wrong, which is the whole point of sending at a fixed time.
#
# THE REPORT IS HANDED OVER EARLY AND SENT LATER. ldgr is normally opened at
# closing time, used for a few minutes to type the day in, and closed again — so
# at the send time it is usually NOT running. The report therefore cannot be
# sent by this program at that moment. Instead, while ldgr is open, the coming
# report is handed to Resend (Resend.jl) with its send time attached, and Resend
# sends it at that time whether or not this computer is still on. Every save
# hands over a fresh version and cancels the one before it, so the version that
# goes out is the one that was current when ldgr was closed. A day on which ldgr
# is opened but nothing is saved still hands over a quiet report, which is how
# "a quiet day still sends" survives the program being closed.
#
# WHAT CAN STILL GO WRONG, AND WHAT HAPPENS THEN. Three things, each handled at
# the next tick after it becomes visible:
#   * A day saved after the last version was handed over — the internet was
#     down, or the save was in the last minute before the send time. The version
#     Resend sent was missing it, so a CORRECTED report goes out at once.
#   * A stretch nothing was handed over for at all — days typed on the command
#     line, a crash, a week offline, Resend refusing. It goes out at once as one
#     LATE report. A stretch in which nothing was saved is not sent on its own —
#     that would be a pointless email about a closed Sunday — it is folded into
#     the coming report, which then says it covers more than one day.
#   * A day ldgr is never opened. Nothing can be sent, and nothing is. The
#     watchdog notices instead: Resend tells healthchecks.io each time a report
#     is delivered, and healthchecks.io emails the owner when a working day
#     passes without one. Neither holds a single figure.
#
# EVERYTHING IS RE-DERIVED, EVERY TICK, from four things that outlive the
# process: notify.toml, the marker (how far reports are known to be complete),
# the state file (which version is waiting at Resend) and the change log.
# Nothing is remembered between ticks except how long to wait after a failure
# and which failure was last said, and when (so it is not said again within the
# hour) — a server restarted at any moment picks up exactly where the last one
# left off, and one that has been up for a week behaves like one started a minute
# ago. Losing those costs one early retry and one repeated sentence.
#
# NOTHING HERE IS A RECORD. Every figure in the report is read back out of the
# change log and the journals; delete the Notifications folder and the books are
# untouched. The report is a reader of the paper trail, never a second copy of
# it (see Changes.jl, which is the trail itself). The owner's inbox is the
# archive of what was sent.
#
# EMAIL IS OFF UNTIL SOMEBODY CONFIGURES IT. No notify.toml — or one with no
# `to` address or no Resend `api_key`, such as the old Gmail settings — and
# `settings()` is `nothing`: every entry point says so and returns, no folder is
# created, and the server's start-up line says why. That is the state a fresh
# copy of this program is in, and the state the tests run in. The change log is
# written either way.
#
# THE API KEY IS NEVER PRINTED, LOGGED OR PUT IN A FILE THIS PROGRAM WRITES. It
# exists in notify.toml, which is git-ignored, and in one request header.
# `_scrub` takes it back out of any text before that text reaches the terminal
# or the audit log.
#
# THIS FILE NEVER TOUCHES THE NETWORK. It decides what to send and when;
# `MAILER[]` does the sending. server.jl puts Resend's two calls there, the tests
# put a fake, and the command line puts nothing — a day typed there is picked up
# by the next server start.
#
# THE FORM KNOWS NOTHING ABOUT ANY OF THIS. No endpoint mentions email, no save
# is slower because of it, and no save can fail because of it. A save nudges the
# scheduler (`poke`), which does its work in the background after the form
# already has its answer.
# =============================================================================

export enabled, build_digest, tick

"""
    MAILER[]

How a report actually leaves the machine: a NamedTuple of two functions,

    send   = (key, email, idempotency_key) -> id
    cancel = (key, id) -> nothing

each throwing on failure — ideally a `Resend.Failure`, whose `kind`
(`:settings` or `:temporary`) decides how long to wait before trying again.

`nothing` until server.jl fills it with Resend's two calls, so that the command
line, and anything else that loads only main.jl, can never send. The tests put
a recording fake in its place, which is the only reason every branch of `tick`
can be exercised without an internet connection or an account.
"""
const MAILER = Ref{Any}(nothing)

"The timer that does the work, while there is one."
const SCHEDULE = Ref{Union{Nothing,Timer}}(nothing)

"""
    BUSY

One tick at a time. The timer and a save's `poke` can both want to run one, and
two ticks racing could each hand over a version and each cancel the other's.
The timer only `trylock`s (a beat skipped is a beat nobody misses); a poke waits,
because the save it follows must be handed over.
"""
const BUSY = ReentrantLock()

"""
    BACKOFF[], CANCEL_BACKOFF[]

When a failed hand-over (or a failed cancel) may be tried again:
`(until, kind, mtime)`, or `nothing`.

After a `:temporary` failure — no internet, Resend down — five minutes: long
enough not to dial out every minute all evening, short enough that a connection
coming back is used. A save's poke does not wait for it, because a save is the
moment a fresh report matters most. After a `:settings` failure — a wrong key, a
wrong address — an hour, OR until notify.toml is saved again, because until a
person changes something the answer will be the same.

With the three audit throttles below (`LAST_TROUBLE`, `LAST_CANCEL_TROUBLE` and
`LAST_UNEXPECTED`), the only state this module keeps in memory. Losing it on a
restart costs one early retry, or one sentence said twice.
"""
const BACKOFF = Ref{Any}(nothing)
const CANCEL_BACKOFF = Ref{Any}(nothing)

"""
    LAST_TROUBLE[], LAST_CANCEL_TROUBLE[]

The last failure written to the audit log (and shown on the terminal with it),
and when — one for hand-overs, one for cancels. The same sentence is not written
again for an hour, so an evening offline is one line, not one every five
minutes. Two, because a hand-over that works must not make a cancel that keeps
failing (a key that can only send) news again on every save.

All three throttles are forgotten when the audit log itself could not be
written (`_flush_audit`): a sentence that never reached the log has not been
said, and the next tick must say it again.
"""
const LAST_TROUBLE = Ref(("", DateTime(0)))
const LAST_CANCEL_TROUBLE = Ref(("", DateTime(0)))

"""
    LAST_UNEXPECTED[]

The same, for an error nobody planned for (a folder that cannot be written, a
journal that cannot be read). An error that comes back on every beat is written
to the audit log once an hour, not once a minute — the audit log is the books'
own trail, and sixty identical lines an hour would bury it. The terminal gets
the sentence at the same moment and no oftener (see `Reported`).
"""
const LAST_UNEXPECTED = Ref(("", DateTime(0)))

"""
    Reported(error)

What `tick` throws for an unexpected error it has already dealt with: the
sentence is in the audit log and, subject to the same once-an-hour throttle
(`LAST_UNEXPECTED`), on the terminal. The timer and `poke` must not warn about
it again — that is what made the terminal say the same thing every minute — so
they recognise this wrapper (`_warn_escaped`) and stay quiet. It prints as the
error it wraps.
"""
struct Reported <: Exception
    error::Any
end
Base.showerror(io::IO, r::Reported) = showerror(io, r.error)

# --- Settings ---------------------------------------------------------------

"""When the report goes out if notify.toml does not say otherwise: half past
five in the evening, clinic time. The clinic is in Guyana and so is the machine,
so the machine's clock is clinic time and there is no daylight saving to cross.
It is after the day is normally typed in; a day typed later than this lands in
the next day's report."""
const DEFAULT_SEND_AT = Time(17, 30)

"""
    _config() -> (settings or nothing, why)

The settings from `notify.toml`, and when there are none, the few words the
server's start-up line uses to say why email is off.

Re-read on each call rather than cached: the file is a few lines, the timer asks
once a minute, and a cached copy would mean editing the settings needed the
server restarted.

EMAIL NEEDS BOTH `to` AND `api_key`. A file with neither is treated exactly like
no file at all. In particular the old Gmail settings (`smtp`, `user`,
`password`) have no `api_key`, so a machine that still has them is simply off —
and says so — rather than trying to use a password that no longer works.

A FILE THAT CANNOT BE PARSED IS OFF, WITH ONE WARNING that names the line but
never quotes it: the line might be the one holding the key.
"""
function _config()
    p = Layout.notify_config_path()
    isfile(p) || return (nothing, "no notify.toml")
    cfg = try
        TOML.parsefile(p)
    catch e
        line = hasproperty(e, :line) ? " (line $(getproperty(e, :line)))" : ""
        @warn "The email settings in notify.toml could not be read$(line), so no report will be sent." maxlog = 1
        return (nothing, "notify.toml could not be read")
    end
    key = _setting(cfg, "api_key")
    isempty(key) && return (nothing, "notify.toml has no Resend api_key")
    to = _setting(cfg, "to")
    isempty(to) && return (nothing, "notify.toml has no to address")
    # NO `from`, NO EMAIL. There used to be a default, Resend's shared testing
    # sender (onboarding@resend.dev). On the first live run (29 September 2026)
    # a scheduled report from it was accepted and then failed at its send time
    # with "Domain is not verified" — out of this program's sight, so only the
    # watchdog would ever have said. A settings file without an address on a
    # domain verified in Resend is not finished, and the start-up line says so.
    from = _setting(cfg, "from")
    isempty(from) && return (nothing, "notify.toml has no from address")
    prefix = get(cfg, "subject_prefix", "ldgr: ")
    return ((to             = to,
             api_key        = key,
             from           = from,
             subject_prefix = prefix isa AbstractString ? String(prefix) : "ldgr: ",
             send_at        = _send_at(get(cfg, "send_at", ""))), "")
end

"One text setting, trimmed, or `\"\"` when it is missing or is not text."
function _setting(cfg, name::AbstractString)
    v = get(cfg, name, "")
    return v isa AbstractString ? String(strip(v)) : ""
end

"""
    settings() -> NamedTuple or nothing

`(to, api_key, from, subject_prefix, send_at)` from notify.toml, or `nothing`
when email is off. See `_config`.
"""
settings() = first(_config())

"""
    _send_at(v) -> Time

The hour the report goes out, read from `"HH:MM"` on a 24-hour clock. A TOML
time written without quotes (`send_at = 17:30:00`) is accepted too, with any
seconds dropped: the state file keeps send times to the second, and a send time
with a fraction of a second in it would never match its own record, so every
tick would hand over a new version.

An unreadable value falls back to the default with one warning rather than
refusing to send at all. The settings file is edited by hand; a typo in the time
should cost the time that was chosen, not the report.
"""
function _send_at(v)
    v isa Time && return Time(Dates.hour(v), Dates.minute(v))
    s = v isa AbstractString ? strip(v) : ""
    isempty(s) && return DEFAULT_SEND_AT
    t = tryparse(Time, s, dateformat"HH:MM")
    if t === nothing
        @warn "The email settings do not give a readable send time (\"HH:MM\"), " *
              "so the report will go out at $(_clock(DEFAULT_SEND_AT))." maxlog = 1
        return DEFAULT_SEND_AT
    end
    return t
end

"True when there is somewhere to send the report and a key to send it with."
enabled() = settings() !== nothing

"Where the report goes, for the line printed when the server starts."
function recipient()
    s = settings()
    return s === nothing ? "" : s.to
end

"The time of day the report goes out, as \"17:30\"."
function send_at_text()
    s = settings()
    return Dates.format(s === nothing ? DEFAULT_SEND_AT : s.send_at, "HH:MM")
end

"""
    banner() -> String

What the server's start-up line says about email, in one of these shapes:

    on -> owner@example.com  (daily report at 17:30, sent by Resend; last complete report: 5:30 pm on 27 September 2026)
    off (no notify.toml)
    off (notify.toml has no Resend api_key)
    off (notify.toml has no to address)
    off (notify.toml has no from address)
    off (notify.toml could not be read)

SAID OUT LOUD AT EVERY START because the failure it guards against is silence:
an owner who believes a report is coming and never learns that the settings were
never finished, or are still the old Gmail ones.
"""
function banner()
    cfg, why = _config()
    cfg === nothing && return "off ($(why))"
    m = last_reported()
    last = m === nothing ? "none yet" : "$(_clock(m)) on $(_long(Date(m)))"
    line = "on -> $(cfg.to)  (daily report at $(Dates.format(cfg.send_at, "HH:MM")), " *
           "sent by Resend; last complete report: $(last))"
    get(ENV, "LDGR_NO_DIGEST", "") == "1" && (line *= "  [not scheduled: LDGR_NO_DIGEST=1]")
    return line
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

A time of day the way a person says it: 5:30 pm, 10:12 am.

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

"""
    _para(io, text; width = 78)

One paragraph, wrapped at `width` columns on word boundaries. For the sentences
that are longer than a line — the notes under the heading and the footer — so
they read as a paragraph in any mail program rather than one line off the edge.
"""
function _para(io, text::AbstractString; width::Int = 78)
    line = ""
    for w in split(text)
        if !isempty(line) && length(line) + 1 + length(w) > width
            println(io, line)
            line = String(w)
        else
            line = isempty(line) ? String(w) : line * " " * w
        end
    end
    isempty(line) || println(io, line)
    return nothing
end

# --- The window -------------------------------------------------------------

"""
    latest_cutoff(t, at) -> DateTime

The most recent moment a report was due, at or before `t`.

Half of the scheduling arithmetic (`next_cutoff` is the other half). Ask it at
any instant and it names the cutoff that should have been covered by now;
compare that with the marker and the answer to "is a stretch uncovered?" falls
out. Nothing is held in memory and nothing counts elapsed minutes.
"""
function latest_cutoff(t::DateTime, at::Time)
    cut = DateTime(Date(t), at)
    return cut <= t ? cut : cut - Day(1)
end

"""
    next_cutoff(t, at) -> DateTime

The first moment a report is due strictly after `t`: the send time the coming
report is handed over for. At the send time exactly it is tomorrow's, because
today's is due that very instant and belongs to `latest_cutoff`.
"""
function next_cutoff(t::DateTime, at::Time)
    cut = DateTime(Date(t), at)
    return cut > t ? cut : cut + Day(1)
end

# --- How far the reports have got -------------------------------------------

"The way the two state files write a moment: to the second, no time zone —
clinic time is the only time there is."
const STAMP = dateformat"yyyy-mm-dd HH:MM:SS"

"""
    last_reported() -> DateTime or nothing

The cutoff up to which reports are known to be complete — handed to Resend and
past their send time — or `nothing` when none has ever been.

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
    t = tryparse(DateTime, String(text), STAMP)
    t === nothing && @warn "The record of the last report does not make sense and was ignored." file = p
    return t
end

"""
    mark_reported!(cutoff)

Write down how far the reports have got.

WRITTEN TO A TEMPORARY FILE AND MOVED INTO PLACE, so the marker is either the
old cutoff or the new one and never half a line.

THE MARKER MOVES ONLY WHEN A REPORT IS KNOWN TO BE COMPLETE: when the version
Resend held has passed its send time and nothing was saved into its stretch
after it was handed over, or when a late, corrected or forced report has been
accepted by Resend. Never when a version is merely handed over — the version
waiting at Resend is recorded separately (`scheduled report.toml`), because it
can still be replaced.
"""
function mark_reported!(cutoff::DateTime)
    p = Layout.digest_marker_path()
    mkpath(dirname(p))
    tmp = Layout.temp_path(p)
    write(tmp, Dates.format(cutoff, STAMP))
    Base.Filesystem.rename(tmp, p)       # not mv(force = true): see `_save_state`
    return nothing
end

"""
    _advance!(t, at)

Move the marker to `t`, but never backwards — unless the marker is in the
future, which only a wrong clock could have written, and which `_marker`
already ignores.
"""
function _advance!(t::DateTime, at::DateTime)
    m = last_reported()
    (m === nothing || m < t || m > at + Minute(5)) && mark_reported!(t)
    return nothing
end

"""
    _marker(at, send_at) -> (marker, note)

The marker as the next report should use it, and a note for that report when
the marker had to be overruled.

A MARKER MORE THAN FIVE MINUTES IN THE FUTURE IS IGNORED. It can only have been
written while the computer's clock was wrong; believed, it would hide every
entry made until the clock caught up with it. The report starts a day before
the latest cutoff instead, and says so, so that whoever reads it knows to look
at the clock.
"""
function _marker(at::DateTime, send_at::Time)
    m = last_reported()
    (m === nothing || m <= at + Minute(5)) && return (m, "")
    start = latest_cutoff(at, send_at) - Day(1)
    note = "The record of the last report was dated $(_clock(m)) on $(_long(Date(m))), which is " *
           "in the future, so it was ignored and this report starts at $(_clock(start)) on " *
           "$(_long(Date(start))). The computer's clock may have been wrong."
    return (start, note)
end

"""
    _repeat_note(unsure, from, cutoff; scheduled) -> String

The sentence a report carries when it may repeat one ldgr gave up on: a
scheduled version handed to Resend whose answer never came back, so ldgr could
neither confirm nor cancel it (`state.unsure`, its send time). `""` when there is
no such version, or when its send time is outside the stretch `(from, cutoff]`
this report covers — a report for another stretch is not a repeat of it.

ONE RULE FOR EVERY REPORT ldgr builds: the late one, the first ever, the
corrected and follow-up ones, one sent on request, and the scheduled one. Each
asks here whether its own stretch contains the send time. The wording depends on
whether the report is going out now (`scheduled = false`: the earlier version
may have been received and sent already) or at its send time (`scheduled = true`:
if the earlier version is still waiting, two reports arrive together). When the
send time is on another day than the report's cutoff, the day is named.

The text feeds the idempotency key, so it depends on nothing but its arguments.
"""
function _repeat_note(unsure::Union{Nothing,DateTime}, from::Union{Nothing,DateTime},
                      cutoff::DateTime; scheduled::Bool = false)
    unsure === nothing && return ""
    ((from === nothing || from < unsure) && unsure <= cutoff) || return ""
    when = _clock(unsure) * (Date(unsure) == Date(cutoff) ? "" : " on $(_long(Date(unsure)))")
    if !scheduled
        return "This report may repeat one sent at $(when): ldgr could not confirm that Resend " *
               "had received it before ldgr was closed or went offline. If both arrived, this " *
               "one is complete."
    elseif unsure == cutoff
        return "Two reports may arrive at $(when): ldgr handed an earlier version of this one to " *
               "Resend but could not confirm that Resend had received it, so it could not cancel " *
               "it. If both arrive, this one is complete."
    else
        return "This report may repeat one sent at $(when): ldgr handed an earlier version to " *
               "Resend but could not confirm that Resend had received it. If both arrive, this " *
               "one is complete."
    end
end

"Notes for one report, the empty ones left out and the rest joined by a space."
_notes(parts::AbstractString...) = join(filter(!isempty, collect(String.(parts))), " ")

# --- The version waiting at Resend ------------------------------------------

"One earlier version still to be cancelled: its Resend id and its send time."
const Leftover = NamedTuple{(:id, :cutoff), Tuple{String, DateTime}}

"""
    Pending

A hand-over that was started and not yet confirmed: written to the state file
BEFORE the email goes to Resend, and cleared in the same write that records the
answer.

  kind        "scheduled", "late", "fix" or "now"
  key         the idempotency key it was sent with
  email       the email exactly as sent: from, to, subject, text, html (only
              when the report had one) and scheduled_at (`""` for one sent at
              once)
  from, cutoff, rows, problem, generation, settings
              what the state would have recorded had the answer arrived
  written     when it was written

WHY IT EXISTS. When the internet drops between Resend creating an email and its
answer arriving, this program cannot know the email exists — and a report
rebuilt a minute later, after one more save, has different content, a different
key, and becomes a second email. Or ldgr is closed first, and the next morning
the report looks as if it was never handed over and goes out again as a "late"
one. Sending the very same request again with the very same key settles the
question: Resend answers with the email it already made, or makes it now if the
first attempt never arrived. So the next tick does exactly that before it
builds anything new.
"""
const Pending = NamedTuple{(:kind, :key, :email, :from, :cutoff, :rows, :problem, :generation,
                            :settings, :written),
                           Tuple{String, String, Dict{String,Any}, Union{Nothing,DateTime}, DateTime,
                                 Int, String, Int, String, DateTime}}

"""
    Scheduled

What `scheduled report.toml` holds:

  id          the Resend id of the version currently waiting, or `""` for none
  cutoff      when it will be sent (clinic time)
  from        the start of the stretch it covers; `nothing` = from the beginning
  rows        how many change-log rows were in that stretch when it was built
  generation  bumped after every successful hand-over; part of the
              idempotency key, so a new version can never be mistaken for an
              old one
  cancel      earlier versions still to be cancelled
  settings    a fingerprint of `to`, `from` and the subject prefix, so editing
              those in notify.toml replaces the waiting version
  problem     what the change log could not be read of when it was built (`""`
              when all of it could), so a problem that appears later — a torn
              line that adds no rows — is still noticed and told
  pending     a hand-over not yet confirmed (see `Pending`), or `nothing`
  unsure      the send time of a version that had to be given up on without
              knowing whether Resend received it, until a report covering that
              send time has gone out; that report says it may repeat the one
              sent then. Kept here, not in memory, because the report may go
              out on a later tick or after a restart. EVERY report built
              while it is set, whose stretch contains that send time — a late
              one, the first ever, a corrected or follow-up one, one sent on
              request, and the next scheduled one — says it may be a repeat
              (`_repeat_note`). It is forgotten once the marker reaches it.
"""
const Scheduled = NamedTuple{(:id, :cutoff, :from, :rows, :generation, :cancel, :settings,
                              :problem, :pending, :unsure),
                             Tuple{String, Union{Nothing,DateTime}, Union{Nothing,DateTime},
                                   Int, Int, Vector{Leftover}, String,
                                   String, Union{Nothing,Pending}, Union{Nothing,DateTime}}}

"Is a version waiting at Resend?"
_waiting(s) = s !== nothing && !isempty(s.id) && s.cutoff !== nothing

"The same record with nothing waiting — kept, not deleted, for its generation
and any earlier versions still to cancel."
_cleared(s::Scheduled) = Scheduled(("", nothing, nothing, 0, s.generation, s.cancel, "", "", nothing, s.unsure))

"The same record with a different list of earlier versions to cancel."
_with_cancel(s::Scheduled, c::Vector{Leftover}) =
    Scheduled((s.id, s.cutoff, s.from, s.rows, s.generation, c, s.settings, s.problem, s.pending, s.unsure))

"The same record with a hand-over started (a `Pending`) or finished (`nothing`)."
_with_pending(s::Scheduled, p::Union{Nothing,Pending}) =
    Scheduled((s.id, s.cutoff, s.from, s.rows, s.generation, s.cancel, s.settings, s.problem, p, s.unsure))

"The same record with an uncertain send time noted (a DateTime) or cleared (`nothing`)."
_with_unsure(s::Scheduled, u::Union{Nothing,DateTime}) =
    Scheduled((s.id, s.cutoff, s.from, s.rows, s.generation, s.cancel, s.settings, s.problem, s.pending, u))

_stamp_text(t) = t === nothing ? "" : Dates.format(t, STAMP)
_stamp_read(v) = (s = strip(string(v)); isempty(s) ? nothing : DateTime(s, STAMP))

"""
    _read_state() -> Scheduled or nothing

`scheduled report.toml`, or `nothing` when it is absent or cannot be read.
Read-only; the warm-up calls it.
"""
function _read_state()
    p = Layout.scheduled_state_path()
    isfile(p) || return nothing
    try
        d = TOML.parsefile(p)
        cancel = Leftover[Leftover((String(c["id"]), _stamp_read(c["cutoff"])))
                          for c in get(d, "cancel", Any[])]
        pending = nothing
        if haskey(d, "pending")
            q = d["pending"]
            m = q["email"]
            email = _email_dict(String(m["from"]), String(first(m["to"])), String(m["subject"]),
                                String(m["text"]), String(get(m, "scheduled_at", "")),
                                String(get(m, "html", "")))
            pending = Pending((String(q["kind"]), String(q["key"]), email,
                               _stamp_read(get(q, "from", "")), _stamp_read(q["cutoff"]),
                               Int(get(q, "rows", 0)), String(get(q, "problem", "")),
                               Int(get(q, "generation", 0)), String(get(q, "settings", "")),
                               _stamp_read(q["written"])))
        end
        return Scheduled((String(get(d, "id", "")),
                          _stamp_read(get(d, "cutoff", "")),
                          _stamp_read(get(d, "from", "")),
                          Int(get(d, "rows", 0)),
                          Int(get(d, "generation", 0)),
                          cancel,
                          String(get(d, "settings", "")),
                          String(get(d, "problem", "")),
                          pending,
                          _stamp_read(get(d, "unsure", ""))))
    catch e
        @warn "The record of the report waiting at Resend could not be read." file = p maxlog = 1
        return nothing
    end
end

"""
    _save_state(s)

Write `scheduled report.toml` to a temporary file and rename it into place, so
it is always either the old record or the new one.

`rename`, NOT `mv(...; force = true)`: on Julia 1.9 the latter deletes the old
file before it renames the new one, so a crash — or an antivirus scanner
holding the new file for a moment — can leave neither. `rename` replaces the
file in one step, and if it cannot, it throws and the old record stays.
"""
function _save_state(s::Scheduled)
    p = Layout.scheduled_state_path()
    mkpath(dirname(p))
    d = Dict{String,Any}("id"         => s.id,
                         "cutoff"     => _stamp_text(s.cutoff),
                         "from"       => _stamp_text(s.from),
                         "rows"       => s.rows,
                         "generation" => s.generation,
                         "settings"   => s.settings,
                         "problem"    => s.problem,
                         "cancel"     => Dict{String,Any}[Dict{String,Any}("id" => c.id,
                                                                           "cutoff" => _stamp_text(c.cutoff))
                                                          for c in s.cancel])
    s.unsure === nothing || (d["unsure"] = _stamp_text(s.unsure))
    q = s.pending
    if q !== nothing
        d["pending"] = Dict{String,Any}("kind"       => q.kind,
                                        "key"        => q.key,
                                        "from"       => _stamp_text(q.from),
                                        "cutoff"     => _stamp_text(q.cutoff),
                                        "rows"       => q.rows,
                                        "problem"    => q.problem,
                                        "generation" => q.generation,
                                        "settings"   => q.settings,
                                        "written"    => _stamp_text(q.written),
                                        "email"      => Dict{String,Any}(
                                            "from"         => q.email["from"],
                                            "to"           => q.email["to"],
                                            "subject"      => q.email["subject"],
                                            "text"         => q.email["text"],
                                            "scheduled_at" => get(q.email, "scheduled_at", "")))
        # Only when there is one: a hand-over written before the HTML body
        # existed has none, and must read back, and be sent again, as it was.
        haskey(q.email, "html") && (d["pending"]["email"]["html"] = q.email["html"])
    end
    tmp = Layout.temp_path(p)
    open(tmp, "w") do io
        println(io, "# Written by ldgr (Notify.jl): the version of the daily report waiting at")
        println(io, "# Resend, and earlier versions still to be cancelled. Not to be edited by hand.")
        println(io)
        TOML.print(io, d; sorted = true)
    end
    Base.Filesystem.rename(tmp, p)
    return nothing
end

"""
    _load_state!(session, at) -> Scheduled

The state for this tick. When there is none yet — or the file cannot be read —
a fresh record is written at once, so that the generation every key is built
from survives a failed first hand-over.

THE FIRST GENERATION IS TAKEN FROM THE CLOCK, not 0. Resend remembers an
idempotency key for a day and answers a repeat with the email it made the first
time — even if that email has since been cancelled. A record that was lost and
restarted from 0 could rebuild the very key it used that morning and be handed a
cancelled report back. A number of seconds cannot repeat.
"""
function _load_state!(session, at::DateTime)
    s = _read_state()
    s === nothing || return s
    isfile(Layout.scheduled_state_path()) &&
        log_event(session, "email: the record of the report waiting at Resend could not be read, " *
                           "so a new one was started. If two reports arrive for one day, the one " *
                           "that includes the later entries is the right one."; echo = false)
    s = Scheduled(("", nothing, nothing, 0, max(1, Dates.value(at - DateTime(2026)) ÷ 1000),
                   Leftover[], "", "", nothing, nothing))
    _save_state(s)
    return s
end

# --- The report -------------------------------------------------------------

"""
    build_digest(from, to; note = "") -> (subject, body)

The one daily report, as plain text, for everything that happened after `from`
and up to `to`. `from === nothing` covers everything there is. `note` is printed
under the heading — the late and corrected reports use it to say why they are
arriving when they are.

READS, NEVER WRITES. It is safe to call at any time, from the warm-up as well as
from the timer.

THE SAME BOOKS GIVE THE SAME BYTES. There is no "prepared at" in it, nothing
from the clock at all: the idempotency key is built from the content, and a
report that changed every minute would be a new email every minute. What tells
the owner how current a report is, is the time of the last entry it includes.

THE FACTS COME FROM TWO PLACES AND ONLY TWO. What happened comes out of the
change log, which is the only thing that knows when. What is still outstanding
comes from a live look at the disk, because a ledger that is waiting is a
standing condition rather than an event — it has to be repeated in every report
until it clears, and an event log can only say when it started.

NO WARNING CODES. L2-A and L3-E are how the program talks to itself. The person
reading this is not looking anything up.
"""
function build_digest(from::Union{Nothing,DateTime}, to::DateTime; note::AbstractString = "")
    rows, problem = Changes.rows_checked(from, to)
    return _digest(rows, problem, from, to; note = note)
end

"""
    build_report(from, to; note = "") -> (subject, text, html)

`build_digest` with the HTML body beside the plain text. The text is the same
bytes `build_digest` gives; the HTML shows the same facts, laid out for a phone
(`EmailHtml.jl`).
"""
function build_report(from::Union{Nothing,DateTime}, to::DateTime; note::AbstractString = "")
    rows, problem = Changes.rows_checked(from, to)
    return _report(rows, problem, from, to; note = note)
end

"""
    _plan(rows) -> NamedTuple

What the report is about, worked out once from the rows and the disk, before
anything is written: which days were entered, which filled a gap, which earlier
days were changed, what is waiting, and the counts the subject line and the
opening sentence are made from. The text and the HTML are two renderings of this
one plan, so they cannot disagree about which day belongs where.

A released day belongs under the day whose entry released it, not under its own
date: the story is "this gap was filled, and here is what that let through".
Everything else is grouped by the day it is about.
"""
function _plan(rows::Vector{Changes.Row})
    waiting = Chain.waiting_ledgers()

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
        elseif any(_reportable, g)
            # An edit in the session the figures were first typed in (before
            # midnight and before the send time that followed) is the owner's
            # idea of an ordinary correction, and is deliberately silent. What
            # is reported is an edit made later, or one made to a day whose
            # ledger nobody has seen yet (`Changes._session_over`).
            push!(changed, d)
        end
    end
    # A save that released a waiting ledger but is in no section yet — an edit,
    # even a same-date one, that let a held day's ledger be made — is told
    # under CHANGES, with the ledger it released: the owner was told the ledger
    # was waiting, and must be told it no longer is.
    for d in keys(released_by)
        (d in gaps || d in changed) || push!(changed, d)
    end
    sort!(changed; rev = true)

    # --- counting, for the subject line and the opening sentence ------------
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

    return (waiting = waiting, released_by = released_by, groups = groups,
            entered = entered, gaps = gaps, changed = changed,
            n_entered = length(entered) + length(gaps), n_changed = length(changed),
            n_waiting = length(waiting), n_diff = n_diff)
end

"""
    _live(key, f)

A live read of the books (`f()`), remembered for the report being built. `_report`
opens a cache (`task_local_storage`), so the text and the HTML are worked out
from one reading of the disk and cannot disagree even if a save lands between
them, and each day is read once instead of once per rendering. With no report
being built (`_digest` on its own) it just reads.
"""
function _live(key, f::Function)
    c = get(task_local_storage(), :ldgr_live_reads, nothing)
    c === nothing && return f()
    return get!(f, c, key)
end

"An edit the owner's rules report: made after the session the day's figures were
first typed in, or while the day's ledger had not been made."
_reportable(r::Changes.Row) = r.cross_day_edit || r.pending_day

"Does this row carry a real difference, on the day or overnight?"
_has_diff(r::Changes.Row) = _real(r.day_diff) || _real(r.night_diff)

"Does the report cover more than one day?"
_spans(from::Union{Nothing,DateTime}, to::DateTime) = from !== nothing && Date(to) - Date(from) > Day(1)

"""
    _digest(rows, problem, from, to; note, corrected) -> (subject, body)

`build_digest` with the rows already read — `tick` reads them once, counts them
for the state file and builds from the same list, so the count it records is
exactly the count the report was built from.

NEVER A FALSE ALL-CLEAR. When the change log could not be read (`problem` is not
empty) the subject says so in capitals, the first thing in the body says the
report may be missing entries, and the "nothing was entered" sentence is left
out: an unreadable log and a quiet day must never look alike.
"""
function _digest(rows::Vector{Changes.Row}, problem::AbstractString,
                 from::Union{Nothing,DateTime}, to::DateTime;
                 note::AbstractString = "", corrected::Bool = false)
    return _text_report(_plan(rows), rows, problem, from, to, note, corrected)
end

"""
    _report(rows, problem, from, to; note, corrected) -> (subject, text, html)

The same report in both forms. `text` is exactly what `_digest` gives — the
record, and what a mail app shows when it will not show HTML — and `html` shows
the same facts, reorganised (`_html_body`).

THE TEXT NEVER DEPENDS ON THE HTML. If the HTML cannot be built, the report goes
out as text alone (an empty `html`), with one warning: a report held up by a
fault in its layout would be worse than one that is merely plainer.
"""
function _report(rows::Vector{Changes.Row}, problem::AbstractString,
                 from::Union{Nothing,DateTime}, to::DateTime;
                 note::AbstractString = "", corrected::Bool = false)
    return task_local_storage(:ldgr_live_reads, Dict{Any,Any}()) do
        _report_cached(rows, problem, from, to, note, corrected)
    end
end

function _report_cached(rows, problem, from, to, note, corrected)
    plan = _plan(rows)
    subject, text = _text_report(plan, rows, problem, from, to, note, corrected)
    html = try
        _html_body(plan, rows, problem, from, to; note = note, corrected = corrected, subject = subject)
    catch e
        e isa InterruptException && rethrow()
        _warn_html(e)
        ""
    end
    return (subject, text, html)
end

"""
    LAST_HTML[]

The last sentence said about an HTML body that could not be built, and when. Said
on the terminal again only when it changes or an hour has passed, like the
failures of a hand-over — a report is built every minute. Nothing is written to
the audit log: the warm-up builds a report too, and may write nothing.
"""
const LAST_HTML = Ref(("", DateTime(0)))

function _warn_html(e)
    words = "The HTML version of the daily report could not be built, so it goes out as plain text only: " *
            _scrub(strip(first(split(sprint(showerror, e), '\n'))))
    said, when = LAST_HTML[]
    now_ = Dates.now()
    (words == said && Millisecond(0) <= now_ - when < Hour(1)) && return nothing
    LAST_HTML[] = (words, now_)
    @warn words
    return nothing
end

function _text_report(plan, rows::Vector{Changes.Row}, problem::AbstractString,
                      from::Union{Nothing,DateTime}, to::DateTime,
                      note::AbstractString, corrected::Bool)
    (; waiting, released_by, groups, entered, gaps, changed,
       n_entered, n_changed, n_waiting, n_diff) = plan

    quiet  = n_entered == 0 && n_changed == 0 && n_waiting == 0
    span   = _spans(from, to)
    unread = !isempty(problem)

    io = IOBuffer()
    if unread
        # FIRST, before the heading, so it is what a phone shows in the preview.
        _para(io, _unread_text(problem))
        println(io)
    end
    println(io, "LDGR DAILY REPORT")
    println(io, "$(_long(Date(to))), $(_covering(from, to))")
    if !isempty(rows)
        # The one line that says how current this report is. If two versions of
        # a report ever both arrive, the one that includes the later entry is
        # the right one.
        latest = maximum(r -> r.when, rows)
        println(io, "Includes everything saved up to $(_clock(latest)) on $(_short(Date(latest))).")
    end
    println(io, "Records folder: $(Layout.ROOT)")
    println(io)
    if !isempty(note)
        _para(io, note)
        println(io)
    end
    if span
        _para(io, _span_text())
        println(io)
    end

    if quiet
        if unread
            # Nothing said: the paragraph at the top has said it cannot tell.
        else
            # One line, not wrapped: it has always been printed as a single line
            # (and is short enough not to need wrapping); the longer sentence for
            # a window of same-date corrections is a paragraph.
            if isempty(rows)
                println(io, _quiet_text(span, false))
            else
                _para(io, _quiet_text(span, true))
            end
            println(io)
        end
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
                _changed_block(io, d, get(groups, d, Changes.Row[]), get(released_by, d, Changes.Row[]))
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
            for line in _WAITING_LINES
                println(io, "   ", line)
            end
            println(io)
        end
    end

    println(io, _rule())
    _para(io, _footer_text())

    summary = _summary(n_entered, n_diff, n_changed, n_waiting)
    subject = _prefix() * (unread ? "CHANGE LOG COULD NOT BE READ — " : "") *
              (corrected ? "corrected report for " : "report for ") * _window(from, to)
    # "nothing to report" beside a log that could not be read would be the very
    # all-clear this report must never give.
    (unread && summary == "nothing to report") || (subject *= " — " * summary)
    return (subject, String(take!(io)))
end

"THE LEAD-IN OF THE PARAGRAPH that says the change log could not be read. It is a
piece of its own because the HTML sets it in bold."
const _UNREAD_LEAD = "THE CHANGE LOG COULD NOT BE READ PROPERLY,"

"The rest of that paragraph, with what could not be read (`problem`) in it."
_unread_rest(problem::AbstractString) =
    " so this report may be missing entries. It is not a quiet day. $(problem) Ask whoever looks " *
    "after ldgr to check \"Change Log.csv\" in the Records folder."

_unread_text(problem::AbstractString) = _UNREAD_LEAD * _unread_rest(problem)

"The paragraph for a report that covers more than one day."
_span_text() = "This report covers more than one day: no report was sent at " *
               "$(_clock(_send_time())) on the days in between, usually because ldgr was " *
               "not opened."

"The sentence for a report with nothing to tell: either nothing at all was
saved in the window, or only same-date corrections were."
function _quiet_text(span::Bool, has_rows::Bool)
    has_rows || return span ? "Nothing was entered or changed, and every recorded day has its ledger." :
                              "Nothing was entered or changed today, and every recorded day has its ledger."
    # Rows, but none the owner's rules report: corrections made on the date a
    # day was first typed, after the report that showed that day. "Nothing was
    # changed" would be untrue, so it is not said.
    return "Nothing new was entered, and every recorded day has its ledger. The only " *
           "changes were corrections made on the same date a day was first typed in, " *
           "which are not reported one by one."
end

"The footer sentence."
_footer_text() = "This report is sent at $(_clock(_send_time())) on each day ldgr is used. If none " *
                 "arrives on a working day, ldgr was not opened that day or the email settings need " *
                 "attention."

"The three lines that explain the list of waiting ledgers, as the text breaks them."
const _WAITING_LINES = ("These days are in the books. Only their ledgers are outstanding, and each",
                        "is made by itself as soon as the day before it is entered. This list",
                        "repeats in every report until it is empty.")

"The configured send time, or the default when email is off — the report says
when it is sent, and the warm-up builds a report with no settings."
function _send_time()
    s = settings()
    return s === nothing ? DEFAULT_SEND_AT : s.send_at
end

# The change log asks for the send time on every save: it is one of the two
# moments a day's free-correction session ends (`Changes._session_over`), and
# this module owns the setting. Registered here rather than passed in by each
# front door, so the server and the command line cannot disagree, and a front
# door that forgot it could not quietly fall back to the midnight-only rule.
Changes.SEND_TIME[] = _send_time

"""
    _covering(from, to) -> String

"covering 14 September 5:30 pm to 15 September 5:30 pm".

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
    _summary_parts(entered, differences, changed, waiting) -> Vector{Pair{Symbol,String}}

Every count that is not zero, in the order the owner cares about them: what it
is (`:entered`, `:differences`, `:changed`, `:waiting`) and how it reads. The
subject line takes the first three (`_summary`); the HTML shows them all.
"""
function _summary_parts(entered::Int, differences::Int, changed::Int, waiting::Int)
    parts = Pair{Symbol,String}[]
    entered     > 0 && push!(parts, :entered     => _count(entered, "day entered", "days entered"))
    differences > 0 && push!(parts, :differences => _count(differences, "difference", "differences"))
    changed     > 0 && push!(parts, :changed     => _count(changed, "day changed", "days changed"))
    waiting     > 0 && push!(parts, :waiting     => _count(waiting, "ledger waiting", "ledgers waiting"))
    return parts
end

"""
    _summary(entered, differences, changed, waiting) -> String

The part of the subject after the dash: at most three counts, in the order the
owner cares about them, and "nothing to report" when there are none.

CAPPED AT THREE because a subject line is read in a list, at a glance, and the
fourth count is always the one the body says better.
"""
function _summary(entered::Int, differences::Int, changed::Int, waiting::Int)
    parts = String[last(p) for p in _summary_parts(entered, differences, changed, waiting)]
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

# --- The facts the blocks are made of ---------------------------------------
# Each of these works a fact out and prints nothing. The text prints them below
# and the HTML lays them out (EmailHtml.jl); neither works anything out for
# itself, so the two renderings cannot say different things.

"""
    _difference_facts(day, row) -> (day, night)

Each difference on one day, either of which may be `nothing`: the one that arose
while the clinic was trading (`word`, `amount`, `reason`) and the one between
last night's close and this morning's open (the same, and `prior`: the
closing balance of the day before and its date, or `nothing` when that day is
missing).

THE TWO DIFFERENCES ARE NEVER MERGED. They have different causes and different
people to ask, and the form asks for a reason for each. The overnight one names
the balance it is being compared with, read live from the books; when the day
before is missing — which is possible for a day entered into a gap — `prior` is
`nothing`, and nothing is worked out in its place: nothing in this program
calculates a closing balance.
"""
function _difference_facts(d::Date, r::Changes.Row)
    day = _real(r.day_diff) ?
          (word = _kind(r.day_diff), amount = _amount(r.day_diff), reason = String(strip(r.reason))) :
          nothing
    night = nothing
    if _real(r.night_diff)
        prior = _live((:prior, d), () -> Chain.prior_day(d))
        night = (word   = r.night_diff < 0 ? "less" : "more",
                 amount = _amount(r.night_diff),
                 prior  = prior === nothing ? nothing :
                          (amount = Checks.money(prior.closing), date = prior.date),
                 reason = String(strip(r.night_reason)))
    end
    return (day = day, night = night)
end

"""
    _day_facts(day, rows) -> NamedTuple

What DAYS ENTERED and GAPS FILLED say about one day.

The LAST row is the state: a day saved and then corrected in the same sitting
shows the figures it ended up with, not the ones it passed through. The FIRST
saved row is who entered it and when (`entry`), because that is the question
being answered; if a later row changed it, that is said separately (`later`).
`state` is `:off`, `:diff` or `:balanced`.
"""
function _day_facts(d::Date, rows::Vector{Changes.Row})
    latest  = rows[end]
    first_i = something(findfirst(r -> r.what == "saved", rows), firstindex(rows))
    state   = latest.kind == "closed" ? :off : _has_diff(latest) ? :diff : :balanced
    return (latest = latest, first_i = first_i, entry = rows[first_i], state = state,
            diffs = _difference_facts(d, latest), later = _later_facts(rows, first_i))
end

"""
    _later_facts(rows, first_i) -> NamedTuple

What happened to a day after its first save (`rows[first_i]`).

An ordinary same-session correction is only "Changed again by …" (`again`, the
row). An edit the owner's rules report — made after that session (on a later
calendar date, or after the send time that followed the first save), or while the
day's ledger was still waiting — is spelled out (`report` is true): `shown`, the
edits from the first such one to the last, `pending` when it is the waiting
ledger that makes it reportable, and `balance`, the before-and-after of a
difference the edits cleared (`_balance_facts`).
"""
function _later_facts(rows::Vector{Changes.Row}, first_i::Int)
    latest = rows[end]
    after  = rows[first_i+1:end]
    if !any(_reportable, after)
        return (report = false, again = isempty(after) ? nothing : latest, pending = false,
                shown = Changes.Row[], balance = nothing)
    end
    shown = _shown_edits(after)
    return (report = true, again = nothing, pending = any(r -> r.pending_day, after),
            shown = shown, balance = _balance_facts(latest, shown))
end

"""
    _shown_edits(rows) -> Vector{Row}

Every edit from the first one the owner's rules report to the last.

EVERY EDIT, NOT JUST THE LAST. Each row's `changed` cell holds only the step
from the save before it, so showing the last one alone would show a second
correction and hide the first — and a second save with nothing changed would
hide the whole thing. The edits after the first reported one are shown too,
same-date or not, so the last "after" figure is always the one in the books.
"""
function _shown_edits(rows::Vector{Changes.Row})
    i = findfirst(_reportable, rows)
    i === nothing && return Changes.Row[]
    return filter(r -> r.what == "edited", rows[i:end])
end

"""
    _edit_parts(row) -> Vector{String}

"What moved" in one edit: the `changed` cell of the log, a list joined with
semicolons, split back out so each figure gets its own line. A reason containing
"; " would split with it, which costs a line break in a sentence nobody is
parsing.

Rows written before the kind of day was worded for people read
`Kind of day trading -> closed`; such a part is printed as
`Kind of day Work day -> Off day`, so old and new rows read alike.
"""
_edit_parts(r::Changes.Row) = String[_legacy_kind(String(strip(p))) for p in split(r.changed, "; ") if !isempty(strip(p))]

const _LEGACY_KIND = r"^Kind of day (trading|closed) -> (trading|closed)$"

function _legacy_kind(part::String)
    m = match(_LEGACY_KIND, part)
    m === nothing && return part
    return "Kind of day $(Changes.kind_words(m[1])) -> $(Changes.kind_words(m[2]))"
end

"""
    _balance_facts(latest, shown) -> NamedTuple or nothing

"It did not balance before … It balances now." for a day one of whose reported
edits cleared a difference, and that still balances: `(was = "shortage of …")`,
with `was` empty when the log does not say what the difference was. Only the
reported edits count: a same-session correction that happened to clear a
difference is as free as any other.
"""
function _balance_facts(latest::Changes.Row, shown::Vector{Changes.Row})
    (any(r -> r.now_balances, shown) && !_has_diff(latest)) || return nothing
    return (was = _was_text(shown, shown),)
end

"""
    _was_text(shown, rows) -> String

What the difference used to be, for a day that has been made to balance: "shortage
of \$50.00 during the day", or `""` when nothing says. Read from the `was` columns,
because by now the books no longer hold it.

TAKEN FROM THE FIRST EDIT PRINTED that carried a difference, so it agrees with
the first before → after line above it and with the difference the owner was
last told — not the in-between state before the edit that finally cleared it.
When no printed edit carries one, the first row that cleared a difference is
used.
"""
function _was_text(shown::Vector{Changes.Row}, rows::Vector{Changes.Row})
    i = findfirst(r -> _real(r.was_day_diff) || _real(r.was_night_diff), shown)
    r = if i !== nothing
        shown[i]
    else
        j = findfirst(x -> x.now_balances, rows)
        j === nothing ? nothing : rows[j]
    end
    r === nothing && return ""
    parts = String[]
    _real(r.was_day_diff)   && push!(parts, "$(lowercase(_kind(r.was_day_diff))) of " *
                                            "$(_amount(r.was_day_diff)) during the day")
    _real(r.was_night_diff) && push!(parts, "$(lowercase(_kind(r.was_night_diff))) of " *
                                            "$(_amount(r.was_night_diff)) overnight")
    return join(parts, ", ")
end

"""
    _released_facts(released) -> Vector{NamedTuple}

Each ledger a save let be made, by day, with any difference that came to light
when it was (`_difference_facts`): the day before it had been missing, so
nothing could be compared until now.
"""
_released_facts(released::Vector{Changes.Row}) =
    [(day = r.day, diffs = _difference_facts(r.day, r)) for r in sort(released; by = x -> x.day)]

"""
    _changed_facts(day, rows, released) -> NamedTuple

What CHANGES TO DAYS ALREADY SAVED says about one day: which day was changed and
when (`when`), when it was first saved (`seen`, a moment or `nothing`), whether
its ledger was waiting (`pending`), the edits to show (`shown`), why a ledger
released by it is told here at all when no edit is (`release_only`: `nothing`,
`:silent` for a correction whose figures are not listed, or `:unread` when the
save that released it could not be read), and then either `balances` with what
the difference `was`, or `differences`, the ones the day still has.
"""
function _changed_facts(d::Date, rows::Vector{Changes.Row}, released::Vector{Changes.Row})
    latest = isempty(rows) ? nothing : rows[end]
    when   = latest === nothing ? first(released).when : latest.when
    shown  = _shown_edits(rows)
    balances = latest !== nothing && any(r -> r.now_balances, rows) && !_has_diff(latest)
    return (latest = latest, when = when, seen = _live((:seen, d), () -> Changes.first_saved_at(d)),
            pending = any(r -> r.pending_day, rows), shown = shown,
            release_only = isempty(shown) && !isempty(released) ? (isempty(rows) ? :unread : :silent) : nothing,
            n_released = length(released),
            balances = balances, was = balances ? _was_text(shown, rows) : "",
            differences = latest !== nothing && !balances ? _difference_facts(d, latest) : nothing,
            released = _released_facts(released))
end

"""
    _waiting_facts(day) -> (day, until)

A ledger that is waiting, and the missing day it is waiting for (`until`), or
`nothing` when the day before it is already on record and the ledger simply has
not been made yet.
"""
_waiting_facts(d::Date) =
    (day = d, until = _live((:on_record, d - Day(1)), () -> Chain.on_record(d - Day(1))) ? nothing : d - Day(1))

# --- The blocks -------------------------------------------------------------

"""
    _entered_block(io, day, rows)

One day under DAYS ENTERED.

A LATER-DATE EDIT IS SPELLED OUT EVEN HERE. A day typed after the send time and
corrected the next morning, before that evening's report, has both rows in one
report. The owner's rule is that an edit made after the session of the first
save (midnight or the send time, whichever came first) is reported with what
moved; so is an edit to a day whose ledger was still waiting. Such an edit is
printed with its before → after figures, the date it was made, and whether it
made the day balance, as CHANGES TO DAYS ALREADY SAVED would have printed it
(`_later_edits`). Only same-session corrections of an ordinary day stay folded
into "Changed again".
"""
function _entered_block(io, d::Date, rows::Vector{Changes.Row})
    f = _day_facts(d, rows)
    headline = f.state == :off ? "Off day." : f.state == :diff ? "does not balance." : "balanced."
    println(io, "$(_long(d)) — $(headline)")
    _print_differences(io, "   ", f.diffs)
    println(io, "   Entered by $(f.entry.who) at $(_clock(f.entry.when)).")
    _print_later(io, f.later)
    println(io)
end

"""
    _later_edits(io, rows, first_i)

What happened to a day after its first save, for the two sections that tell a
day by its entry: DAYS ENTERED and GAPS FILLED (`_later_facts`).
"""
_later_edits(io, rows::Vector{Changes.Row}, first_i::Int) = _print_later(io, _later_facts(rows, first_i))

function _print_later(io, f)
    if !f.report
        f.again === nothing ||
            println(io, "   Changed again by $(f.again.who) at $(_clock(f.again.when)).")
        return nothing
    end
    f.pending &&
        println(io, "   Its ledger had not been made yet — it was waiting on the day before it.")
    _print_edits(io, f.shown)
    _print_balance(io, f.balance)
    return nothing
end

"""
    _edit_lines(io, rows) -> Vector{Row}

Every edit from the first one the owner's rules report to the last, each on its
own line with the date, the person and the time, and under it what moved from
what to what. Returns the rows printed.
"""
function _edit_lines(io, rows::Vector{Changes.Row})
    shown = _shown_edits(rows)
    _print_edits(io, shown)
    return shown
end

function _print_edits(io, shown::Vector{Changes.Row})
    for r in shown
        parts = _edit_parts(r)
        println(io, "   Changed on $(_long(Date(r.when))) by $(r.who) at $(_clock(r.when))",
                    isempty(parts) ? ", with no figure different." : ":")
        for part in parts
            println(io, "      ", part)
        end
    end
    return nothing
end

function _print_balance(io, b)
    b === nothing && return nothing
    isempty(b.was) || println(io, "   It did not balance before: $(b.was).")
    println(io, "   It balances now.")
    return nothing
end

"""
    _difference_lines(io, pad, day, row)

Each difference on one day, in its own words, with the reason typed for it
(`_difference_facts`).
"""
_difference_lines(io, pad::AbstractString, d::Date, r::Changes.Row) =
    _print_differences(io, pad, _difference_facts(d, r))

function _print_differences(io, pad::AbstractString, f)
    if f.day !== nothing
        println(io, pad, "$(f.day.word) of $(f.day.amount) during the day.")
        _reason_line(io, pad * "   ", f.day.reason)
    end
    if f.night !== nothing
        n = f.night
        if n.prior === nothing
            println(io, pad, "The opening balance is $(n.amount) $(n.word) than ",
                        "the day before closed with.")
        else
            println(io, pad, "The opening balance is $(n.amount) $(n.word) than ",
                        "the $(n.prior.amount) the day before closed with.")
        end
        _reason_line(io, pad * "   ", f.night.reason)
    end
    return nothing
end

"The typed explanation, tucked under the difference it explains. `pad` is the
exact indent, because the two places this is used sit at different depths."
function _reason_line(io, pad::AbstractString, reason::AbstractString)
    text = strip(reason)
    println(io, pad, "reason: ", isempty(text) ? "(none given)" : text)
end

"""
    _changed_block(io, day, rows, released = [])

One day under CHANGES TO DAYS ALREADY SAVED.

This is the section the whole exercise was built for. It says which day was
changed, when it was first saved, why the change is being reported at all, what
moved, and whether the change cleared a difference the owner had already been
told about.

Each edit is printed with who made it, when, and what moved (`_print_edits`),
so two corrections in one stretch are both shown and neither hides the other.

`released` is the ledgers this day's edit let be made. An edit that released a
ledger is told here even when it is a same-session correction whose figures the
owner's rules keep silent: the figures stay unlisted, but the ledger that came
out of it is named, because the owner was told it was waiting.
"""
function _changed_block(io, d::Date, rows::Vector{Changes.Row},
                        released::Vector{Changes.Row} = Changes.Row[])
    f = _changed_facts(d, rows, released)
    println(io, "$(_long(d)) was changed on $(_long(Date(f.when))).")

    # The time is given when the day was first saved on the date it was changed:
    # an ordinary day changed on the date it was typed is reported because the
    # send time came between the two, and "first saved … at 4:10 pm" beside
    # "Changed … at 6:10 pm" shows that.
    f.seen === nothing ||
        println(io, "   It was first saved on $(_long(Date(f.seen)))",
                Date(f.seen) == Date(f.when) ? " at $(_clock(f.seen))." : ".")
    f.pending &&
        println(io, "   Its ledger had not been made yet — it was waiting on the day before it.")

    _print_edits(io, f.shown)
    if f.release_only !== nothing
        what = f.n_released == 1 ? "a waiting ledger" : "waiting ledgers"
        if f.release_only === :unread
            # The save that released it could not be read (see the top of the
            # report); only the release itself is known.
            println(io, "   A save of this day let ", what, " be made.")
        else
            println(io, "   It was corrected on the date it was first typed in, which let ", what, " be made.")
        end
    end

    if f.latest !== nothing
        if f.balances
            isempty(f.was) || println(io, "   It did not balance before: $(f.was).")
            println(io, "   It balances now.")
        else
            _print_differences(io, "   ", f.differences)
        end
    end
    _print_released(io, f.released)
    println(io)
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

A later-date or pending-day edit of the gap day itself is spelled out here too
(`_later_edits`), exactly as under DAYS ENTERED. A backlog typed in backwards
fills a gap with every day, and each of those days is also waiting on the one
before it, so this is where such edits most often land.
"""
function _gap_block(io, d::Date, rows::Vector{Changes.Row}, released::Vector{Changes.Row})
    f = _day_facts(d, rows)

    println(io, "$(_long(d)) was entered on $(_long(Date(f.entry.when))), filling a gap:")
    println(io, "$(_long(d + Day(1))) was already on record and waiting for it.")
    f.latest.kind == "closed" && println(io, "   It was an Off day.")
    _print_differences(io, "   ", f.diffs)
    println(io, "   Entered by $(f.entry.who) at $(_clock(f.entry.when)).")
    _print_later(io, f.later)
    _print_released(io, _released_facts(released))
    println(io)
end

"""
    _released_lines(io, released)

Each ledger a save let be made, with any difference that came to light when it
was — the day before it had been missing, so nothing could be compared until
now — and the reason on record for it.
"""
_released_lines(io, released::Vector{Changes.Row}) = _print_released(io, _released_facts(released))

function _print_released(io, facts)
    for f in facts
        println(io, "   The ledger for $(_long(f.day)) was made.")
        if f.diffs.day !== nothing
            println(io, "      $(f.diffs.day.word) of $(f.diffs.day.amount) during that day.")
            _reason_line(io, "      ", f.diffs.day.reason)
        end
        if f.diffs.night !== nothing
            n = f.diffs.night
            if n.prior === nothing
                println(io, "      Its opening balance is $(n.amount) $(n.word) than")
                println(io, "      the day before it closed with.")
            else
                println(io, "      Its opening balance is $(n.amount) $(n.word) than the")
                println(io, "      $(n.prior.amount) that $(_long(n.prior.date)) closed with.")
            end
            _reason_line(io, "      ", n.reason)
        end
    end
    return nothing
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
    f = _waiting_facts(d)
    if f.until !== nothing
        println(io, "$(_long(d)) — saved, but its ledger cannot be made until")
        println(io, "   $(_long(f.until)) is entered.")
    else
        println(io, "$(_long(d)) — saved, but its ledger has not been made yet.")
        println(io, "   The day before it is already on record.")
    end
    println(io)
end

include("EmailHtml.jl")

# --- The schedule -----------------------------------------------------------

"""
    tick(; at = nothing, force = false, poked = false) -> Vector{Symbol}

One beat of the clock: settle what is due, send what is owed, and make sure the
coming report is waiting at Resend. Returns what it did, in order:

  :off        no notify.toml, or one without `to` and `api_key`. Nothing is
              written and no folder is created.
  :no_mailer  nothing to send with (`MAILER[]` is empty: the command line).
  :waiting    a recent failure says not to try again yet.
  :cancelled  an earlier version was cancelled at Resend.
  :settled    the version Resend sent was complete; the marker moved on.
  :sent       a corrected report (or, with `force`, a report of everything so
              far) was sent there and then.
  :late       a stretch nothing covered was sent there and then.
  :scheduled  a new version of the coming report was handed over.
  :failed     something could not be handed over; it will be tried again.
  :idle       nothing needed doing — the ordinary answer.

EVERYTHING IS RE-DERIVED, EVERY TIME, from notify.toml, the marker, the state
file and the change log, so a server restarted at any moment picks up exactly
where the last one left off. The steps, in order:

  0. A hand-over whose answer never arrived is sent again, word for word, with
     the same idempotency key (see `Pending`), and its answer recorded, before
     anything new is built.
  1. Cancel earlier versions still waiting at Resend. One whose send time has
     passed is dropped, and the audit log says it may also have been sent.
  2. Settle the version whose send time has come. If the change log holds as
     many rows for its stretch as it was built from, and no problem reading it
     that the version did not already state, it was complete: the marker moves
     to its cutoff. If it holds more rows, something was saved after it was
     handed over, and a CORRECTED report is sent at once; if part of the log
     has become unreadable, a follow-up saying so is sent at once.
  3. A stretch that ended before now and that nothing covered — days typed on
     the command line, a crash, a week offline — is sent at once as one LATE
     report, if anything was saved in it. If nothing was, it is folded into the
     coming report instead of costing the owner an email about nothing.
  4. The coming report — everything since the marker, up to the next send
     time — is handed to Resend to be sent at that time, unless the version
     already waiting there covers the same stretch with the same rows and the
     same reading of the log. The new version is handed over FIRST and the old
     one cancelled after, so there is never a moment with nothing waiting.
     Within a minute of the send time nothing is handed over: a save that late
     is caught by step 2 as a correction.

A SEND TIME COUNTS AS PASSED ONLY ONCE ITS WHOLE SECOND IS OVER. The change log
stamps rows to the second, so a save written at 5:30:00.6 belongs to the 5:30
report; a tick at 5:30:00.2 that settled it would leave that save in no report
at all.

THE CLOCK IS READ ONCE THE LOCK IS HELD, not when the call is made: a save's
poke can wait behind a tick that is itself waiting on a slow network, and a time
read before the wait could hand over a report whose send time has already come.

`force` (`LDGR_DIGEST_NOW=1`, for a manual check) sends everything since the
marker there and then instead of step 3, and step 4 then starts again from now.
`poked` marks a tick asked for by a save, which does not wait out the pause
after a temporary failure.

An unexpected error inside the steps is written to the audit log and the terminal
(once an hour) and thrown as `Reported`, wrapping the original.
"""
function tick(; at::Union{Nothing,DateTime} = nothing, force::Bool = false, poked::Bool = false)
    lock(BUSY) do
        started = Dates.now()
        _tick(at === nothing ? started : at, force, poked, started)
    end
end

function _tick(at::DateTime, force::Bool, poked::Bool, started::DateTime)
    cfg = settings()
    cfg === nothing && return [:off]
    mailer = MAILER[]
    mailer === nothing && return [:no_mailer]
    _held_back(BACKOFF[], at, poked) && return [:waiting]

    did = Symbol[]
    session = AuditSession(Layout.audit_log_path())
    try
        _steps!(did, session, cfg, mailer, at, force, started)
    catch e
        # Not a failure to reach Resend (those are handled where they happen)
        # but something unexpected. Written to the audit log, and shown on the
        # terminal at the same moment — once an hour at most, like every other
        # failure — and then thrown as `Reported`, so that the timer and `poke`
        # do not warn about it again on every beat.
        _trouble!(session, "the daily report could not be prepared: " *
                           _scrub(strip(first(split(sprint(showerror, e), '\n')))), at, LAST_UNEXPECTED)
        throw(Reported(e))
    finally
        _flush_audit(session)
    end
    LAST_UNEXPECTED[] = ("", DateTime(0))
    isempty(did) && push!(did, :idle)
    return did
end

function _steps!(did::Vector{Symbol}, session, cfg, mailer, at::DateTime, force::Bool,
                 started::DateTime)
    state = _load_state!(session, at)
    fp = _fingerprint(cfg)

    # The last whole second that is over. See the docstring.
    ripe = floor(at, Second) - Second(1)

    # 0. A hand-over whose answer never came. One given up on leaves its send
    #    time in `state.unsure`, so every report built after it whose stretch
    #    contains that time — a corrected, follow-up, late, first-ever or
    #    requested one, on this tick or a later one, or the next scheduled
    #    version — says it may be a repeat (`_repeat_note`).
    if state.pending !== nothing
        state = _resolve_pending!(did, session, cfg, mailer, state, at)
        state === nothing && return            # still unanswered: try again later
    end

    # 1. Earlier versions still waiting at Resend. Straight after step 0 has
    #    confirmed a scheduled hand-over, the version it replaced must go now,
    #    whatever the pause after an earlier failed cancel says — as in step 4.
    state = _cancel_leftovers!(did, session, cfg, mailer, state, at, !(:scheduled in did))

    # 2. The version whose time has come.
    if _waiting(state) && state.cutoff <= ripe
        rows, problem = Changes.rows_checked(state.from, state.cutoff)
        grew  = length(rows) > state.rows
        fresh = !isempty(problem) && problem != state.problem
        if grew || fresh
            # More rows than the version was built from: a save landed in its
            # stretch after it was handed over. A problem the version did not
            # state: part of the log has become unreadable since, and it may
            # have held an entry. Fewer rows and no new problem cannot happen
            # with an append-only log, and is no reason to send a second report.
            note = grew ?
                "This replaces the report sent at $(_clock(state.cutoff)), which was prepared " *
                "before the last entry of that day could be sent." :
                "This follows the report sent at $(_clock(state.cutoff)). When ldgr checked it " *
                "afterwards, part of the change log for that stretch could not be read, so that " *
                "report may have left an entry out."
            # A version given up on for this very send time is the likeliest
            # reason for a correction (its answer was lost, so it was never
            # replaced), and the owner may now hold three reports for it.
            note = _notes(note, _repeat_note(state.unsure, state.from, state.cutoff))
            ok, state = _send_now!(session, cfg, mailer, state, at, "fix", state.from, state.cutoff,
                                   rows, problem; note = note, corrected = grew)
            if !ok
                push!(did, :failed)
                return
            end
            log_event(session, "email: " * (grew ? "a corrected report" : "a follow-up report") *
                               " for $(_window(state.from, state.cutoff)) was sent, because " *
                               (grew ? "something was saved after the last version was handed over" :
                                       "part of the change log could not be read") *
                               " ($(_saved_up_to(rows)))"; echo = false)
            push!(did, :sent)
        else
            log_event(session, "email: the report for $(_long(Date(state.cutoff))), sent by Resend at " *
                               "$(_clock(state.cutoff)), " *
                               (isempty(state.problem) ? "held every entry up to that time" :
                                "already said the change log could not be read properly");
                      echo = false)
            push!(did, :settled)
        end
        _advance!(state.cutoff, at)
        state = _cleared(state)
        _save_state(state)
    end

    marker, marker_note = _marker(at, cfg.send_at)

    if force
        # 5. Everything since the marker, now.
        upto = floor(at, Second)
        rows, problem = Changes.rows_checked(marker, upto)
        ok, state = _send_now!(session, cfg, mailer, state, at, "now", marker, upto, rows, problem;
                               note = _notes(marker_note, _repeat_note(state.unsure, marker, upto)))
        if !ok
            push!(did, :failed)
            return
        end
        log_event(session, "email: a report covering $(_window(marker, upto)) was sent on request " *
                           "(LDGR_DIGEST_NOW)"; echo = false)
        mark_reported!(upto)
        marker, marker_note = upto, ""
        push!(did, :sent)
    else
        # 3. A stretch that closed with nothing covering it.
        due = latest_cutoff(ripe, cfg.send_at)
        if marker === nothing || marker < due
            rows, problem = Changes.rows_checked(marker, due)
            # An unreadable log is sent too: it cannot say the stretch was empty.
            if !isempty(rows) || !isempty(problem)
                again = _repeat_note(state.unsure, marker, due)
                why = if marker === nothing
                    _notes("This is the first report since email was set up, so it covers everything in " *
                           "the change log up to $(_clock(due)) on $(_long(Date(due))).", again)
                elseif !isempty(again)
                    again
                else
                    "This report is late: it could not be sent at $(_clock(due)), usually because " *
                    "ldgr was closed or offline before it could hand the report over."
                end
                note = isempty(marker_note) ? why : why * " " * marker_note
                ok, state = _send_now!(session, cfg, mailer, state, at, "late", marker, due, rows,
                                       problem; note = note)
                if !ok
                    push!(did, :failed)
                    return
                end
                log_event(session, "email: a late report covering $(_window(marker, due)) was sent " *
                                   "($(_saved_up_to(rows)))"; echo = false)
                _advance!(due, at)
                marker, marker_note = due, ""
                push!(did, :late)
            end
        end
    end

    # The uncertain send time is forgotten once the marker has reached it, that
    # is, once a report covering it is out — or the version waiting for it has
    # been settled. This is the only place it is cleared.
    if state.unsure !== nothing && marker !== nothing && marker >= state.unsure
        state = _with_unsure(state, nothing)
        _save_state(state)
    end

    # 4. The coming report — never for a send time the marker has already
    #    passed, which only a clock stepped backwards could otherwise produce.
    next = next_cutoff(marker === nothing ? ripe : max(ripe, marker), cfg.send_at)
    rows, problem = Changes.rows_checked(marker, next)
    if _waiting(state) && state.cutoff == next && isequal(state.from, marker) &&
       state.rows == length(rows) && state.settings == fp && state.problem == problem
        return
    end
    # Judged against the time now, not when the tick began: steps 0 to 3 may
    # have spent a minute waiting on the network.
    next - (at + (Dates.now() - started)) < Minute(1) && return

    # A version already given up on for a send time this report covers may still
    # be waiting at Resend, with no id to cancel it by, so this one says so. The
    # note is not a reason to rebuild: a version already waiting when `unsure`
    # was set is left as it is (the test above ignores `unsure`), and a version
    # handed over later carries it because it is worked out here, from state.
    subject, body, html = _report(rows, problem, marker, next;
                                  note = _notes(marker_note,
                                                _repeat_note(state.unsure, marker, next; scheduled = true)))
    email = _email(cfg, subject, body; scheduled_at = _utc_text(next), html = html)
    gen = state.generation + 1
    key = "ldgr-" * _stamp(next) * "-g$(gen)-" * _hash16(email)
    state = _with_pending(state, Pending(("scheduled", key, email, marker, next, length(rows),
                                          String(problem), gen, fp, at)))
    _save_state(state)
    id = try
        String(mailer.send(cfg.api_key, email, key))
    catch e
        _failed!(session, e, at, BACKOFF)
        # A refusal, or a request that never left this computer, made nothing;
        # only a request that may have reached Resend stays pending, to be
        # asked about again.
        _nothing_made(e) && (state = _with_pending(state, nothing); _save_state(state))
        push!(did, :failed)
        return
    end
    _recovered!()
    state = _adopt!(session, state, id, state.pending)
    push!(did, :scheduled)

    # The version it replaces is cancelled straight away, whatever the pause
    # after an earlier failed cancel says: this is the moment it matters.
    _cancel_leftovers!(did, session, cfg, mailer, state, at, false)
    return
end

"""
    _adopt!(session, state, id, p) -> Scheduled

Record a scheduled version Resend has confirmed as the one now waiting — the
previous one, if any, moves to the list to cancel — and clear the pending
hand-over, in one write.
"""
function _adopt!(session, state::Scheduled, id::String, p::Pending)
    cancel = copy(state.cancel)
    _waiting(state) && state.id != id && push!(cancel, Leftover((state.id, state.cutoff)))
    state = Scheduled((id, p.cutoff, p.from, p.rows, p.generation, cancel, p.settings, p.problem, nothing,
                       state.unsure))
    _save_state(state)
    log_event(session, "email: the report for $(_long(Date(p.cutoff))) was handed to Resend, to be sent " *
                       "at $(_clock(p.cutoff)) ($(_saved_up_to_count(p)))"; echo = false)
    return state
end

"`_saved_up_to` for a pending hand-over, whose rows are no longer in hand."
_saved_up_to_count(p::Pending) =
    (m = match(r"Includes everything saved up to ([^.\n]+)\.", p.email["text"]);
     m === nothing ? "nothing saved in it" : "includes everything saved up to $(m.captures[1])")

"""
    _resolve_pending!(did, session, cfg, mailer, state, at) -> Scheduled or nothing

Step 0: ask Resend again about a hand-over whose answer never arrived, with the
same email and the same key, and record the answer as the first attempt would
have. `nothing` when it is still unanswered — the tick stops there, because a
new version built now could become a second email. A scheduled version given
up on without an answer leaves its send time in `state.unsure`.

A hand-over more than 23 hours old is given up on: Resend forgets a key after a
day, and a repeat after that could make a second email instead of finding the
first. A refusal is given up on too — nothing was made. Either way the audit
log says so.
"""
function _resolve_pending!(did::Vector{Symbol}, session, cfg, mailer, state::Scheduled, at::DateTime)
    p = state.pending
    if p.kind == "scheduled" && p.cutoff - at < Minute(1)
        # Its send time has come. Sent again now, it would carry a send time in
        # the past, which Resend might send at once unlabelled, hold, or refuse.
        # Dropped instead: step 2 or step 3 then sends what is owed as a
        # labelled corrected or late report.
        log_event(session, "email: whether Resend received the version of the report for " *
                           "$(_long(Date(p.cutoff))) could not be confirmed before $(_clock(p.cutoff)), " *
                           "so what it held is sent again as a corrected or late report; if two " *
                           "reports arrive for that day, the one that includes the later entries is " *
                           "the right one"; echo = false)
        state = _with_unsure(_with_pending(state, nothing), p.cutoff)
        _save_state(state)
        return state
    end
    if at - p.written > Hour(23)
        log_event(session, "email: whether Resend received the report for $(_long(Date(p.cutoff))) " *
                           "could not be confirmed in time; if two reports arrive for that day, the " *
                           "one that includes the later entries is the right one"; echo = false)
        state = _with_pending(state, nothing)
        p.kind == "scheduled" && (state = _with_unsure(state, p.cutoff))
        _save_state(state)
        return state
    end
    id = try
        String(mailer.send(cfg.api_key, p.email, p.key))
    catch e
        if _failure_kind(e) === :settings
            _trouble!(session, _failure_words(e), at, LAST_TROUBLE)
            log_event(session, "email: the report for $(_long(Date(p.cutoff))) was refused when it was " *
                               "asked about again, so it was not made"; echo = false)
            state = _with_pending(state, nothing)
            _save_state(state)
            return state
        end
        _failed!(session, e, at, BACKOFF)
        push!(did, :failed)
        return nothing
    end
    _recovered!()
    if p.kind == "scheduled"
        push!(did, :scheduled)
        return _adopt!(session, state, id, p)
    end
    # A report that was to go at once: it has gone, so do what its success
    # would have done.
    what = p.kind == "fix" ? "a corrected report" : p.kind == "late" ? "a late report" : "a report"
    log_event(session, "email: $(what) covering $(_window(p.from, p.cutoff)) was sent (confirmed " *
                       "when it was asked about again)"; echo = false)
    _advance!(p.cutoff, at)
    if p.kind == "fix" && _waiting(state) && state.cutoff == p.cutoff
        state = _cleared(state)
    end
    push!(did, p.kind == "late" ? :late : :sent)
    state = _with_pending(state, nothing)
    _save_state(state)
    return state
end

"""
    _send_now!(session, cfg, mailer, state, at, kind, from, to, rows, problem; note, corrected)
        -> (ok, state)

Build one report and hand it to Resend to go out immediately (no
`scheduled_at`). `kind` names it in the idempotency key — "fix", "late" or
"now" — so that the three can never share a key with each other or with a
scheduled version. The hand-over is written down as pending first (see
`Pending`). `ok` is false, with the failure logged, when it could not be sent.
"""
function _send_now!(session, cfg, mailer, state::Scheduled, at::DateTime, kind::String,
                    from::Union{Nothing,DateTime}, to::DateTime,
                    rows::Vector{Changes.Row}, problem::AbstractString;
                    note::AbstractString = "", corrected::Bool = false)
    subject, body, html = _report(rows, problem, from, to; note = note, corrected = corrected)
    email = _email(cfg, subject, body; html = html)
    key = "ldgr-$(kind)-" * _stamp(to) * "-" * _hash16(email)
    state = _with_pending(state, Pending((kind, key, email, from, to, length(rows), String(problem),
                                          state.generation, _fingerprint(cfg), at)))
    _save_state(state)
    try
        mailer.send(cfg.api_key, email, key)
    catch e
        _failed!(session, e, at, BACKOFF)
        if _nothing_made(e)
            state = _with_pending(state, nothing)
            _save_state(state)
        end
        return (false, state)
    end
    _recovered!()
    state = _with_pending(state, nothing)
    _save_state(state)
    return (true, state)
end

"""
    _cancel_leftovers!(did, session, cfg, mailer, state, at, wait) -> state

Cancel each earlier version still waiting at Resend, and write down which are
left. `wait` honours the pause after a failed cancel; step 4 passes `false`,
because straight after a new version is handed over is when the old one must
go.

A VERSION WHOSE SEND TIME HAS PASSED IS DROPPED: Resend has sent it or never
will, and cancelling is no longer possible either way. The audit log says so,
so that two reports for one day have an explanation. After the first failure
the rest are left for the next tick — if one cancel could not reach Resend, the
next would not either.
"""
function _cancel_leftovers!(did::Vector{Symbol}, session, cfg, mailer, state::Scheduled,
                            at::DateTime, wait::Bool)
    isempty(state.cancel) && return state
    held = wait && _held_back(CANCEL_BACKOFF[], at, false)
    keep = Leftover[]
    stuck = false
    tried = false
    for c in state.cancel
        if c.cutoff <= at
            log_event(session, "email: an earlier version of the report for $(_long(Date(c.cutoff))) " *
                               "could not be cancelled before $(_clock(c.cutoff)), so it may also " *
                               "have been sent"; echo = false)
            continue
        end
        if held || stuck
            push!(keep, c)
            continue
        end
        tried = true
        try
            mailer.cancel(cfg.api_key, c.id)
            log_event(session, "email: an earlier version of the report for " *
                               "$(_long(Date(c.cutoff))) was cancelled"; echo = false)
            push!(did, :cancelled)
        catch e
            push!(keep, c)
            stuck = true
            _failed!(session, e, at, CANCEL_BACKOFF)
        end
    end
    if tried && !stuck
        # Cancels work again: no pause, and the next cancel failure is news.
        CANCEL_BACKOFF[] = nothing
        LAST_CANCEL_TROUBLE[] = ("", DateTime(0))
    end
    keep == state.cancel && return state
    state = _with_cancel(state, keep)
    _save_state(state)
    return state
end

# --- When something goes wrong ----------------------------------------------

"`:settings` when the failure says a person must fix something, else `:temporary`."
function _failure_kind(e)
    k = hasproperty(e, :kind) ? getproperty(e, :kind) : nothing
    return k === :settings ? :settings : :temporary
end

"The failure's own sentence (a `Resend.Failure` has one), or the first line of
any other error — never with the key in it."
function _failure_words(e)
    words = hasproperty(e, :words) ? string(getproperty(e, :words)) :
            "The report could not be handed to Resend: " *
            strip(first(split(sprint(showerror, e), '\n')))
    return _scrub(words)
end

"""
    _nothing_made(e) -> Bool

Did this failure certainly make nothing at Resend? A refusal (`:settings`) made
nothing, and neither did a request that never left this computer (a
`Resend.Failure` with `reached == false`: no internet, no connection). Only
then may a pending hand-over be forgotten instead of asked about again.
"""
_nothing_made(e) = _failure_kind(e) === :settings ||
                   (hasproperty(e, :reached) && getproperty(e, :reached) === false)

"The notify.toml timestamp, so a `:settings` pause can end the moment a person
saves the file."
_config_mtime() = (p = Layout.notify_config_path(); isfile(p) ? mtime(p) : 0.0)

"""
    _held_back(pause, at, poked) -> Bool

True while a pause after a failure is still running. A `:settings` pause ends
early when notify.toml is saved again; a `:temporary` one does not hold back a
save's poke.
"""
function _held_back(pause, at::DateTime, poked::Bool)
    pause === nothing && return false
    at >= pause.until && return false
    pause.kind === :settings && return _config_mtime() == pause.mtime
    return !poked
end

"""
    _failed!(session, e, at, which)

Start a pause in `which` (`BACKOFF` or `CANCEL_BACKOFF`) and say what went wrong
— once. The audit log and the terminal get the sentence when it is new, or when
an hour has passed since it was last said, and not otherwise.
"""
function _failed!(session, e, at::DateTime, which::Ref)
    kind = _failure_kind(e)
    which[] = (until = at + (kind === :settings ? Minute(60) : Minute(5)),
               kind = kind, mtime = _config_mtime())
    _trouble!(session, _failure_words(e), at, which === CANCEL_BACKOFF ? LAST_CANCEL_TROUBLE : LAST_TROUBLE)
    return nothing
end

"""
    _trouble!(session, words, at, last)

Write a failure's sentence to the audit log and the terminal — unless `last`
says the same sentence was written less than an hour ago. `warn = false` leaves
the terminal out.

The throttle is stamped here, when the line is queued; the write itself is
`_flush_audit`'s, and it forgets the stamps when the log could not be written.
"""
function _trouble!(session, words::AbstractString, at::DateTime, last::Ref; warn::Bool = true)
    said, when = last[]
    (words == said && Millisecond(0) <= at - when < Hour(1)) && return nothing
    last[] = (String(words), at)
    log_event(session, "email: " * words; echo = false)
    warn && @warn words
    return nothing
end

"A hand-over worked: no more pause, and the next failure is news again."
function _recovered!()
    BACKOFF[] = nothing
    LAST_TROUBLE[] = ("", DateTime(0))
    return nothing
end

"""
    _flush_audit(session) -> Bool

Write this tick's lines to the audit log as one block, if there are any. A log
that cannot be written costs a warning, never the tick. `false` when it could
not be written.

A FAILURE THAT NEVER REACHED THE LOG HAS NOT BEEN SAID. `_trouble!` stamps its
once-an-hour throttle when it queues a line, before this writes it; had the
write failed and the stamp stayed, the same failure would stay silent for an
hour after the log was mended. So the three throttles are forgotten, and the
next tick says it again.
"""
function _flush_audit(session)
    isempty(session.events) && return true
    try
        log_entry(session; header = "email")
    catch e
        LAST_TROUBLE[] = ("", DateTime(0))
        LAST_CANCEL_TROUBLE[] = ("", DateTime(0))
        LAST_UNEXPECTED[] = ("", DateTime(0))
        @warn "The audit log could not be written." exception = e
        return false
    end
    return true
end

"""
    _scrub(text) -> String

Any text about to be printed or logged, with the Resend API key taken out of
it. Resend.jl never puts the key in its sentences; this makes sure that nothing
else can either — a fake in the tests, an error from somewhere unexpected.
Anything shaped like a Resend key is masked as well (`re_` and at least eight
more letters, digits or underscores): a key cut short, or one notify.toml no
longer holds.
"""
function _scrub(text::AbstractString)
    cfg = settings()
    t = (cfg === nothing || length(cfg.api_key) < 8) ? String(text) :
        replace(String(text), cfg.api_key => "********")
    return replace(t, r"\bre_[A-Za-z0-9_]{8,}" => "********")
end

# --- The email itself -------------------------------------------------------

"""
    _email(cfg, subject, body; scheduled_at, html) -> Dict

The JSON body of one Resend email. `scheduled_at` is left out for a report that
goes now, and `html` when there is none (`""`).
"""
function _email(cfg, subject::AbstractString, body::AbstractString;
                scheduled_at::Union{Nothing,String} = nothing, html::AbstractString = "")
    return _email_dict(cfg.from, cfg.to, subject, body, scheduled_at === nothing ? "" : scheduled_at, html)
end

"""
    _email_dict(from, to, subject, text, scheduled_at, html = "") -> Dict

The one place an email body is put together, so a hand-over asked about again
(see `Pending`) is rebuilt key for key in the same order and writes the very
same JSON as the first attempt — a repeated idempotency key with a body that
differed would be refused. `scheduled_at == ""` leaves it out, and so does an
empty `html`: the plain text is always there, and the HTML is a second version
of it that mail apps show in preference.
"""
function _email_dict(from::AbstractString, to::AbstractString, subject::AbstractString,
                     text::AbstractString, scheduled_at::AbstractString, html::AbstractString = "")
    e = Dict{String,Any}("from"    => String(from),
                         "to"      => String[String(to)],
                         "subject" => _utf8(subject),
                         "text"    => _utf8(text))
    isempty(html) || (e["html"] = _utf8(html))
    isempty(scheduled_at) || (e["scheduled_at"] = String(scheduled_at))
    return e
end

"""
Text that is valid UTF-8, whatever it was handed: an invalid byte becomes the
replacement character. The state file (TOML) refuses invalid text outright, and
one stray byte in a reason would otherwise stop every report from being handed
over. Valid text comes back unchanged, so a replay stays byte-identical.
"""
_utf8(s::AbstractString) = isvalid(s) ? String(s) : String(map(c -> isvalid(c) ? c : '\ufffd', s))

"""
    _hash16(email) -> String

The first sixteen hex digits of the SHA-256 of `from|to|subject|text|scheduled_at`,
and `|html` after it when the email has an HTML body — the part of an idempotency
key that is the content. Identical content gives an identical key, which is what
makes a retry after a lost reply harmless; different content can never share
one. An email with no HTML hashes exactly as it did before there was any, so a
hand-over written down by an older version is asked about under the same key.
"""
function _hash16(email::AbstractDict)
    canonical = join((email["from"], join(email["to"], ","), email["subject"], email["text"],
                      get(email, "scheduled_at", "")), "|")
    haskey(email, "html") && (canonical *= "|" * email["html"])
    return bytes2hex(sha256(canonical))[1:16]
end

"A cutoff in the idempotency key: 202609281730."
_stamp(t::DateTime) = Dates.format(t, "yyyymmddHHMM")

"""
    _utc_offset() -> Minute

This machine's clock minus UTC, now, to the minute: `-240` in Guyana. Worked
out when it is needed rather than written down as four hours, so a machine set
to another time zone still schedules for its own evening.
"""
_utc_offset() = Minute(round(Int, Dates.value(Dates.now() - Dates.now(Dates.UTC)) / 60_000))

"""
    _utc_text(t; offset) -> String

A clinic-time moment the way Resend's `scheduled_at` wants it:
`2026-09-28T21:30:00.000Z` for 5:30 pm in Guyana.
"""
function _utc_text(t::DateTime; offset::Minute = _utc_offset())
    u = t - offset
    return Dates.format(u, "yyyy-mm-dd") * "T" * Dates.format(u, "HH:MM:SS") * ".000Z"
end

"A fingerprint of the settings that change the email but not the send time."
_fingerprint(cfg) = bytes2hex(sha256(join((cfg.to, cfg.from, cfg.subject_prefix), "|")))[1:16]

"How current a version is, for the audit log."
function _saved_up_to(rows::Vector{Changes.Row})
    isempty(rows) && return "nothing saved in it"
    t = maximum(r -> r.when, rows)
    return "includes everything saved up to $(_clock(t)) on $(_short(Date(t)))"
end

# --- The timer --------------------------------------------------------------

"""
    start_schedule!()

Start the once-a-minute timer. Called from `start()` after the warm-up and
before the server begins listening.

A TIMER AS WELL AS THE SAVES. Saves `poke` it so a day typed just before ldgr
is closed is handed over within seconds; the timer settles what is due, retries
what failed, and hands over a quiet report on a day nothing is saved.

FIVE SECONDS FOR THE FIRST BEAT, then every minute. The first beat catches up
whatever happened while ldgr was closed.

ONLY ONE TIMER, EVER. Including server.jl a second time in the same REPL defines
the modules afresh but leaves the old timer running the old code, and two
schedulers would each hand over versions and cancel each other's. So the timer
is also recorded in `Main.LDGR_REPORT_TIMER`, which outlives a re-include, and
any timer found there is closed before a new one starts.

THE CALLBACK CANNOT THROW. A timer whose callback throws is cancelled, silently,
and no report is ever handed over again for the life of the process.

`LDGR_NO_DIGEST=1` switches it off, which is what every test run sets.
`LDGR_DIGEST_NOW=1` makes the first beat send a report of everything so far
there and then, for a manual end-to-end check.
"""
function start_schedule!()
    get(ENV, "LDGR_NO_DIGEST", "") == "1" && return nothing
    stop_schedule!()
    force_first = Ref(get(ENV, "LDGR_DIGEST_NOW", "") == "1")
    t = Timer(5; interval = 60) do _
        try
            trylock(BUSY) || return
            try
                force = force_first[]
                force_first[] = false
                tick(; force = force)
            finally
                unlock(BUSY)
            end
        catch e
            _warn_escaped(e)
        end
    end
    SCHEDULE[] = t
    Core.eval(Main, :(global LDGR_REPORT_TIMER = $t))
    return nothing
end

"""
    stop_schedule!()

Stop the timer — this module's, and any left in `Main.LDGR_REPORT_TIMER` by an
earlier include of server.jl. Only the tests and a REPL session need this; a
server that is shutting down takes the timer with it.
"""
function stop_schedule!()
    t = SCHEDULE[]
    t === nothing || close(t)
    SCHEDULE[] = nothing
    if isdefined(Main, :LDGR_REPORT_TIMER)
        old = getfield(Main, :LDGR_REPORT_TIMER)
        old isa Timer && close(old)
        Core.eval(Main, :(global LDGR_REPORT_TIMER = nothing))
    end
    return nothing
end

"""
    poke()

A save has just been written: hand the report over again, in the background.

Returns at once. Nothing happens unless the scheduler is running (so the tests,
and `LDGR_NO_DIGEST=1`, stay silent). The tick runs in its own task and waits
its turn for `BUSY`, so the save's answer to the form never waits on the
network — and a day typed right before ldgr is closed is with Resend within
seconds.
"""
function poke()
    SCHEDULE[] === nothing && return nothing
    @async try
        tick(; poked = true)
    catch e
        _warn_escaped(e)
    end
    return nothing
end

"""
    _warn_escaped(e)

What the timer and `poke` do with an error that came out of `tick`: warn about
it on the terminal — unless it is a `Reported` one, which `tick` has already
said, once an hour, together with its audit line. An error that escapes from
somewhere `tick`'s own catch does not cover (the settings could not be read,
the lock failed) is still warned about, every time: nothing else would say it.
Never throws — a throwing timer callback ends the timer silently, and a throwing
`poke` task is lost.
"""
function _warn_escaped(e)
    e isa Reported && return nothing
    try
        @warn "The daily report could not be prepared: " * _scrub(sprint(showerror, e))
    catch
    end
    return nothing
end

end # module Notify
