# Included inside `module Notify` (Notify.jl), after the text helpers. It is not a
# module of its own: it uses the same `_long`, `_clock`, `_covering`, facts and
# wording as the plain text, and it is tested through the same functions.

# =============================================================================
# EMAILHTML — the daily report as an HTML body, beside the plain text.
#
# THE PLAIN TEXT IS THE RECORD; THIS IS THE SAME REPORT LAID OUT FOR A PHONE. It
# shows the facts the text shows, with the omissions the owner chose on
# 2026-09-30 (handoff/email-html-round2.md lists them, and the parity test names
# each one). Nothing here works a fact out — the grouping is `_plan`, and each
# day's facts are the ones the text prints (`_day_facts`, `_changed_facts`,
# `_difference_facts`, `_waiting_facts`). The design and its reasons are in
# handoff/email-html-design.md and, where the two differ, handoff/email-html-round2.md.
#
# ONE KIND OF CARD. Every day the report is about — entered, a gap filled, an
# earlier day revised, a day whose kind changed, a day whose ledger is waiting —
# is a card of the same shape under one heading, newest date first: the date and
# what happened on the left, status tags on the right, and under them, across the
# card, what an edit changed. Colour lives in the tags, and every tag carries
# words as well: colour never carries meaning alone.
#
# EVERY ELEMENT CARRIES ITS OWN INLINE STYLE. Mail apps drop what they do not
# like: the one <style> block in the head only adds dark colours for the apps
# that honour prefers-color-scheme (through the classes on the elements), and if
# an app throws it away the email is the light design, complete.
#
# EVERY FILL IS SET TWICE, with a `bgcolor` attribute AND `background-color`,
# never the `background` shorthand: Gmail's draft store dropped the shorthand and
# left white text on nothing. (A <span> cannot take `bgcolor`, so a tag's fill is
# its `background-color` alone.)
#
# NOTHING IS LOST AND NOTHING IS TRUSTED. Every dynamic string is escaped
# (`_e`) once; a `changed` part the layout cannot parse is shown as it stands,
# never dropped. No images, no links, no fonts to fetch, nothing from the clock:
# the same books give the same bytes, which the idempotency key depends on.
# =============================================================================

# --- Escaping and small pieces ----------------------------------------------

"Text safe to put in HTML: `&`, `<`, `>`, `\"` and `'` are entities."
_e(s::AbstractString) =
    replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&#39;")

"Escaped, with each line break of a typed reason kept as a `<br>`."
_e_lines(s::AbstractString) = replace(_e(s), r"\r\n|\r|\n" => "<br>")

const _MONTH_ALTERNATIVES = join((Dates.monthname(m) for m in 1:12), "|")

"""
    _nbsp(s) -> String

No-break spaces inside a time (`5:30 pm`) and between a day and its month
(`29 September`), so "pm" or a month never wraps onto a line of its own. Applied
to text the program wrote and already escaped, never to what somebody typed.
"""
_nbsp(s::AbstractString) =
    replace(replace(String(s), r"(\d{1,2}:\d{2}) (am|pm)\b" => s"\1&nbsp;\2"),
            Regex("\\b(\\d{1,2}) ($(_MONTH_ALTERNATIVES))\\b") => s"\1&nbsp;\2")

"A sentence the program wrote: escaped, with its times and dates kept together."
_prose(s::AbstractString) = _nbsp(_e(s))

"""
    _clock24(t) -> String

A time of day as the HTML shows it, on the 24-hour clock with two digits for the
hour: `09:05`, `17:30`. The plain text keeps `_clock` ("9:05 am").
"""
_clock24(t) = Dates.format(t, "HH:MM")

# ldgr's own 12-hour format ("5:30 pm"), as `_clock` writes it.
const _AMPM = r"\b(1[0-2]|[1-9]):([0-5]\d) (am|pm)\b"

"""
    _times24(s) -> String

The 12-hour times in a sentence ldgr wrote ("5:30 pm") as 24-hour ones ("17:30").
ONLY for sentences the program generated — the notes, which arrive from the text
side with `_clock`'s words. Never for what staff typed (a reason may say
"5:30 pm") and never for the change log's `problem`.
"""
_times24(s::AbstractString) =
    replace(String(s), _AMPM => m -> (x = match(_AMPM, m);
                                      h = parse(Int, x[1]) % 12 + (x[3] == "pm" ? 12 : 0);
                                      string(lpad(h, 2, '0'), ":", x[2])))

"`_prose` for a sentence the program wrote that may hold a 12-hour time."
_prose24(s::AbstractString) = _prose(_times24(s))

_hlong(d::Date)  = _nbsp(_long(d))
_hshort(d::Date) = _nbsp(_short(d))
_hclock(t)       = _clock24(t)

"A date the way the bullets and the title band write it: `24-09-2026`."
_hdash(d) = Dates.format(Date(d), "dd-mm-yyyy")

"The kind of day, in the words the form uses."
_kind_words(kind::AbstractString) = kind == "closed" ? "Off day" : "Work day"

const _SPACER = "<tr><td height=\"12\" style=\"font-size:0;line-height:0;\">&nbsp;</td></tr>\n"
const _SPACER16 = "<tr><td height=\"16\" style=\"font-size:0;line-height:0;\">&nbsp;</td></tr>\n"
const _TABLE  = "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\""

"""
    _pill(text, tone; small = false) -> String

A status tag: words in a rounded tint. `tone` is `:danger` (red), `:warn` (amber),
`:ok` (green) or `:neutral`. Never wraps (`white-space:nowrap`).
"""
function _pill(text::AbstractString, tone::Symbol; small::Bool = false)
    cls, bg, fg = tone === :danger ? ("ld ldb", "#FBEDE9", "#A63D40") :
                  tone === :warn   ? ("lw lwb", "#FDF4E3", "#8A6212") :
                  tone === :ok     ? ("la lb",  "#E8F3EE", "#1F6F5C") :
                                     ("ls lq",  "#EFEDE7", "#5B6660")
    size = small ? "font-size:12px;line-height:16px;padding:1px 8px;" : "font-size:12px;line-height:18px;padding:2px 9px;"
    return "<span class=\"$(cls)\" style=\"display:inline-block;background-color:$(bg);color:$(fg);$(size)" *
           "font-weight:700;border-radius:999px;white-space:nowrap;\">$(text)</span>"
end

_soft(text::AbstractString, margin::AbstractString = "10px", size::Integer = 13) =
    "<div class=\"ls\" style=\"margin-top:$(margin);font-size:$(size)px;line-height:$(size + 6)px;color:#5B6660;\">$(text)</div>\n"

# --- The words of a difference ------------------------------------------------

"""
    _tag_text(which, word, amount) -> String

`CB Shortage (\$2,000.00)` or `OB Surplus \$1,000.00`: a shortage in parentheses,
the accounting negative; a surplus plain. `which` is `"CB"` (the closing count
differs from the day's own figures) or `"OB"` (the opening differs from the last
close); `word` is `"Shortage"` or `"Surplus"`.
"""
_tag_text(which::AbstractString, word::AbstractString, amount::AbstractString) =
    word == "Shortage" ? "$(which) Shortage ($(amount))" : "$(which) Surplus $(amount)"

"""
    _diff_tags(diffs) -> Vector{Tuple{String,Symbol}}

The tags of a day's differences (`_difference_facts`), the opening above the
closing. An opening that is LESS than the last close is a shortage, as the text's
"less" is.
"""
function _diff_tags(diffs)
    out = Tuple{String,Symbol}[]
    if diffs.night !== nothing
        n = diffs.night
        short = n.word == "less"
        push!(out, (_tag_text("OB", short ? "Shortage" : "Surplus", n.amount), short ? :danger : :warn))
    end
    if diffs.day !== nothing
        d = diffs.day
        push!(out, (_tag_text("CB", d.word, d.amount), d.word == "Shortage" ? :danger : :warn))
    end
    return out
end

"A difference as an edit shows it: a shortage in parentheses, a surplus plain, nothing as `\$0.00`."
function _signed(v::Float64)
    x = _real(v) ? v : 0.0
    return x < 0 ? "($(Checks.money(abs(x))))" : Checks.money(abs(x))
end

"""
    _diff_label(which, was, now) -> String

The label of a difference row in a change table: `CB Shortage` when both sides
are a shortage or nothing, `CB Surplus` when both are a surplus or nothing, else
`CB Difference` (it turned from one into the other).
"""
function _diff_label(which::AbstractString, was::Float64, now::Float64)
    a = _real(was) ? was : 0.0
    b = _real(now) ? now : 0.0
    return a <= 0 && b <= 0 ? "$(which) Shortage" : a >= 0 && b >= 0 ? "$(which) Surplus" : "$(which) Difference"
end

"Did a difference change between `was` and `now`? A blank counts as nothing."
_diff_moved(was::Float64, now::Float64) =
    !Checks.is_zero_money((_real(was) ? was : 0.0) - (_real(now) ? now : 0.0))

"""
    _explained(diffs) -> String

How the first sentence about a day ends when it has a difference: ` with
explanation: …` for one, ` with explanations: OB – …; CB – …` for two, and
`, no explanation given` when none of them was explained. An empty one among two
says `no explanation given` on its own. `diffs` need only carry `reason`s.
"""
function _explained(diffs)
    parts = Tuple{String,String}[]
    diffs.night === nothing || push!(parts, ("OB", diffs.night.reason))
    diffs.day === nothing   || push!(parts, ("CB", diffs.day.reason))
    isempty(parts) && return ""
    all(p -> isempty(p[2]), parts) && return ", no explanation given"
    length(parts) == 1 && return " with explanation: " * _e_lines(parts[1][2])
    return " with explanations: " * join(("$(w) &ndash; " * (isempty(r) ? "no explanation given" : _e_lines(r))
                                          for (w, r) in parts), "; ")
end

# --- What happened to a day afterwards ---------------------------------------

const _FIGURE_PART = r"^(.+?) (\$[0-9,]+\.[0-9]{2}|\(not counted\)) -> (\$[0-9,]+\.[0-9]{2}|\(not counted\))$"
const _KIND_PART   = r"^Kind of day (.+) -> (.+)$"
const _REASON_PART = r"^(Reason|Night reason) \"(.*)\" -> \"(.*)\"$"s

"""
    _edit_rows(parts) -> Vector{NamedTuple}

The parts of one edit's `changed` cell, each sorted into the shape it is shown
in: a figure (`:three`, label, before, after), the kind of day (`:kind`, the same
three), an explanation (`:reason`, stacked, `which` `:cb` or `:ob`) or — for
anything the layout cannot read — the part exactly as it stands (`:verbatim`). A
part is never dropped here.
"""
function _edit_rows(parts::Vector{String})
    out = NamedTuple[]
    for p in parts
        if (m = match(_FIGURE_PART, p)) !== nothing
            push!(out, (shape = :three, label = _e(m[1]), before = _e(m[2]), after = _e(m[3])))
        elseif (m = match(_KIND_PART, p)) !== nothing
            push!(out, (shape = :kind, label = "Day type", before = _e(_kind_of(m[1])),
                        after = _e(_kind_of(m[2]))))
        elseif (m = match(_REASON_PART, p)) !== nothing
            push!(out, (shape = :reason, which = m[1] == "Reason" ? :cb : :ob,
                        label = m[1] == "Reason" ? "Explanation" : "OB explanation",
                        before = String(m[2]), after = String(m[3])))
        else
            push!(out, (shape = :verbatim, text = p))
        end
    end
    return out
end

"A kind of day in the form's words. Takes the stored words too (`trading`, `closed`),
because `_edit_parts` already words old log rows, but a part must never depend on that;
anything else as it is."
_kind_of(v::AbstractString) = v == "trading" ? "Work day" : v == "closed" ? "Off day" : String(v)

"""
    _html_parts(row) -> Vector{String}

The parts of one edit, as the HTML shows them. The text splits the `changed`
cell on "; " and lives with a reason that contains one (it costs a line break);
here the pieces are put back together: a piece starts a new part only when it
begins the way a part begins (`Reason "`, `Night reason "`, `Kind of day `, or a
figure's label followed by an amount or "(not counted)"), and anything else is
a continuation of the part before it.
"""
function _html_parts(r::Changes.Row)
    labels = String[label_of(k) for k in JOURNAL_KEYS if !(k in VARIANCE_KEYS)]
    starts(f) = occursin(r"^(Reason|Night reason) \"", f) || startswith(f, "Kind of day ") ||
                any(l -> startswith(f, l * " \$") || startswith(f, l * " (not counted)"), labels)
    out = String[]
    for f in _edit_parts(r)
        (isempty(out) || starts(f)) ? push!(out, f) : (out[end] *= "; " * f)
    end
    return out
end

"Did this edit change the kind of day?"
_kind_changed(r::Changes.Row) = any(p -> match(_KIND_PART, p) !== nothing, _html_parts(r))

const _ROW_TOP = "border-top:1px solid #EFEDE7;"

"The small BEFORE / AFTER lead-in of a stacked explanation."
_before_after(word::AbstractString; ink::Bool = false) =
    ink ? "<span class=\"ls\" style=\"display:inline-block;min-width:48px;font-size:11px;letter-spacing:.8px;" *
          "text-transform:uppercase;color:#5B6660;\">$(word)</span> " :
          "<span style=\"display:inline-block;min-width:48px;font-size:11px;letter-spacing:.8px;" *
          "text-transform:uppercase;\">$(word)</span> "

"""
    _edit_table(r; caption) -> String

What one reported edit changed, as a table of label | BEFORE (struck through) |
AFTER (bold), or `""` when the edit moved nothing the layout can show.

THE ROWS, in this order: the figures that moved; a row for each difference the
edit changed (`OB Shortage | (\$2,000.00) | \$0.00`), which the log keeps in its
`was_…` and `…_diff` columns rather than in `changed`; then the explanations,
stacked, except one that was CLEARED, which the first-save sentence already
shows. An edit that changed the KIND of day shows only `Day type | Work day |
Off day`: the figures of a day that is now open or closed are not the story.
With several edits each table carries a small caption saying which edit it is.
"""
function _edit_table(r::Changes.Row; caption::Bool = false)
    rows = _edit_rows(_html_parts(r))
    kind = any(x -> x.shape === :kind, rows)
    body = IOBuffer()
    three(label, before, after) =
        println(body, "<tr><td class=\"li lr\" style=\"$(_ROW_TOP)padding:9px 8px 9px 0;font-size:14px;line-height:20px;",
                      "color:#1C2521;\">$(label)</td>",
                      "<td class=\"ls lr\" align=\"right\" style=\"$(_ROW_TOP)padding:9px 8px;font-size:14px;",
                      "line-height:20px;color:#5B6660;white-space:nowrap;\"><s>$(before)</s></td>",
                      "<td class=\"li lr\" align=\"right\" style=\"$(_ROW_TOP)padding:9px 0 9px 8px;font-size:14px;",
                      "line-height:20px;font-weight:700;color:#1C2521;white-space:nowrap;\">$(after)</td></tr>")
    nthree = 0
    for x in rows
        if x.shape === :kind
            three(x.label, x.before, x.after); nthree += 1
        elseif x.shape === :three && !kind
            three(x.label, x.before, x.after); nthree += 1
        elseif x.shape === :verbatim
            println(body, "<tr><td colspan=\"3\" class=\"li lr\" style=\"$(_ROW_TOP)padding:9px 0;font-size:14px;",
                          "line-height:20px;color:#1C2521;word-wrap:break-word;\">$(_e(x.text))</td></tr>")
        end
    end
    if !kind
        for (which, was, now) in (("OB", r.was_night_diff, r.night_diff), ("CB", r.was_day_diff, r.day_diff))
            _diff_moved(was, now) || continue
            three(_diff_label(which, was, now), _e(_signed(was)), _e(_signed(now))); nthree += 1
        end
        for x in rows
            x.shape === :reason || continue
            isempty(strip(x.after)) && continue            # cleared: the first-save sentence shows it
            before = isempty(strip(x.before)) ? "(none)" : "<s>$(_e_lines(strip(x.before)))</s>"
            println(body, "<tr><td colspan=\"3\" class=\"lr\" style=\"$(_ROW_TOP)padding:9px 0;\">",
                          "<div class=\"li\" style=\"font-size:14px;line-height:20px;color:#1C2521;\">$(x.label)</div>",
                          "<div class=\"ls\" style=\"margin-top:2px;font-size:14px;line-height:20px;color:#5B6660;",
                          "word-wrap:break-word;\">$(_before_after("Before"))$(before)</div>",
                          "<div class=\"li\" style=\"font-size:14px;line-height:20px;color:#1C2521;",
                          "word-wrap:break-word;\">$(_before_after("After"; ink = true))",
                          "<strong>$(_e_lines(strip(x.after)))</strong></div></td></tr>")
        end
    end
    inner = String(take!(body))
    isempty(inner) && return ""
    io = IOBuffer()
    caption && println(io, "<div class=\"ls\" style=\"margin-top:10px;font-size:12px;line-height:16px;color:#5B6660;\">",
                           "Changed on $(_hdash(r.when)) at $(_hclock(r.when))</div>")
    println(io, _TABLE, " style=\"margin-top:$(caption ? 4 : 10)px;\">")
    if nthree > 0
        println(io, "<tr><td style=\"padding:0 8px 4px 0;\"></td>",
                    "<td class=\"ls\" align=\"right\" style=\"padding:0 8px 4px;font-size:11px;line-height:14px;",
                    "letter-spacing:.8px;text-transform:uppercase;color:#5B6660;\">Before</td>",
                    "<td class=\"ls\" align=\"right\" style=\"padding:0 0 4px 8px;font-size:11px;line-height:14px;",
                    "letter-spacing:.8px;text-transform:uppercase;color:#5B6660;\">After</td></tr>")
    end
    print(io, inner)
    println(io, "</table>")
    return String(take!(io))
end

# --- Cards -------------------------------------------------------------------

"Opens a card. Its fill is set twice, `bgcolor` and `background-color`."
function _card_open(io; padding::AbstractString = "16px 14px")
    println(io, "<tr><td class=\"lc\" bgcolor=\"#FFFFFF\" style=\"$(_CARD_STYLE)border-radius:12px;padding:$(padding);\">")
end

const _CARD_STYLE = "background-color:#FFFFFF;border:1px solid #E3E0D8;"

_card_close(io) = println(io, "</td></tr>")

"""
A section heading: `tone` is `:danger` (red, for what could not be trusted) or
`:accent` (the brand green).
"""
function _label(io, text::AbstractString, tone::Symbol)
    cls, col = tone === :danger ? ("ld", "#A63D40") : ("la", "#1F6F5C")
    println(io, "<tr><td style=\"padding:24px 4px 8px;\"><span class=\"$(cls)\" style=\"font-size:14px;",
                "line-height:18px;letter-spacing:1.2px;text-transform:uppercase;font-weight:700;color:$(col);\">",
                "$(text)</span></td></tr>")
end

"""
    _bullets(items) -> String

Event bullets: soft ink, 13px on 19px, a narrow bullet cell and a text cell per
row (a `<ul>` is drawn unevenly by mail apps). `items` are HTML already.
"""
function _bullets(items::Vector{String})
    isempty(items) && return ""
    io = IOBuffer()
    println(io, _TABLE, " style=\"margin-top:6px;\">")
    for text in items
        println(io, "<tr><td class=\"ls\" width=\"14\" valign=\"top\" style=\"width:14px;font-size:13px;line-height:19px;",
                    "color:#5B6660;\">&bull;</td><td class=\"ls\" style=\"font-size:13px;line-height:19px;",
                    "color:#5B6660;word-wrap:break-word;\">$(text)</td></tr>")
    end
    println(io, "</table>")
    return String(take!(io))
end

"""
    _card_facts(d, plan) -> NamedTuple

Everything one day's card is made of, from the facts the text prints. A day with a
`saved` row in the window is an entered day or a gap filled (`_day_facts`); any
other is an earlier day that was revised (`_changed_facts`).

  - `entry`, the saving row, and `entry_diffs`, its differences, only for a day
    entered in this report. When a reported edit follows, the sentence about the
    entry describes the day AS IT WAS ENTERED and the change table what moved;
    otherwise it describes the day as it ended up.
  - `shown`, the reported edits; `balance`, whether one of them cleared a
    difference and the day balances now.
  - `first_diffs`, for a revised day: the differences it had before the first
    reported edit, with the explanation then in force (the before side of that
    edit's explanation part, else the explanation its own row carries).
"""
function _card_facts(d::Date, plan)
    rows     = get(plan.groups, d, Changes.Row[])
    released = get(plan.released_by, d, Changes.Row[])
    common = (day = d, gap = d in plan.gaps, waiting = d in plan.waiting, released = _released_facts(released))
    if any(r -> r.what == "saved", rows)
        f = _day_facts(d, rows)
        return merge(common, (entered = true, entry = f.entry, latest = f.latest, state = f.state,
                              diffs = f.diffs, again = f.later.again, shown = f.later.shown,
                              balance = f.later.balance,
                              entry_diffs = f.later.report ? _difference_facts(d, f.entry) : f.diffs,
                              seen = nothing, first_diffs = nothing))
    end
    c = _changed_facts(d, rows, released)
    latest = c.latest
    state = latest === nothing ? :none : latest.kind == "closed" ? :off : _has_diff(latest) ? :diff : :balanced
    shown = c.shown
    return merge(common, (entered = false, entry = nothing, latest = latest, state = state,
                          diffs = latest === nothing ? nothing : _difference_facts(d, latest),
                          again = nothing, shown = shown,
                          balance = latest === nothing || isempty(shown) ? nothing : _balance_facts(latest, shown),
                          entry_diffs = nothing, seen = c.seen,
                          first_diffs = isempty(shown) ? nothing : _first_diffs(shown[1])))
end

"""
    _first_diffs(r) -> NamedTuple

The differences a day had BEFORE the edit `r` (its `was_…` columns), each with the
explanation in force then: the before side of the edit's explanation part when it
changed one, else the explanation the row itself carries (the edit left it alone).
"""
function _first_diffs(r::Changes.Row)
    reasons = Dict{Symbol,String}(x.which => String(strip(x.before))
                                  for x in _edit_rows(_html_parts(r)) if x.shape === :reason)
    cb = get(reasons, :cb, String(strip(r.reason)))
    ob = get(reasons, :ob, String(strip(r.night_reason)))
    return (day   = _real(r.was_day_diff)   ? (reason = cb,) : nothing,
            night = _real(r.was_night_diff) ? (reason = ob,) : nothing)
end

"""
    _tags(c) -> Vector{Tuple{String,Symbol}}

The status tags of a card, top to bottom. Precedence: a change of the kind of day
is `Work status update` and nothing else; otherwise a reported edit decides
between `Balanced` (it cleared a difference) and `Numbers revised`; otherwise the
day's own state (`Off day`, the opening and closing differences, or `Balanced`).

A DAY WHOSE LEDGER IS WAITING says `Ledger pending` instead of `Balanced` or
`Numbers revised` (the owner's wording for that card), keeping only what the
owner still needs beside it: an Off day, or the opening and closing differences.
"""
function _tags(c)
    tags = Tuple{String,Symbol}[]
    if any(_kind_changed, c.shown)
        push!(tags, ("Work status update", :warn))
    elseif c.waiting
        c.state === :off  && push!(tags, ("Off day", :neutral))
        c.state === :diff && append!(tags, _diff_tags(c.diffs))
        push!(tags, ("Ledger pending", :warn))
        return tags
    elseif !isempty(c.shown)
        push!(tags, c.balance !== nothing ? ("Balanced", :ok) : ("Numbers revised", :warn))
    elseif c.state === :off
        push!(tags, ("Off day", :neutral))
    elseif c.state === :diff
        append!(tags, _diff_tags(c.diffs))
    elseif c.state === :balanced
        push!(tags, ("Balanced", :ok))
    end
    c.waiting && push!(tags, ("Ledger pending", :warn))
    return tags
end

"The words after the date: `(Previous Gap Day)`, `(Awaiting Gap Day)`, `(Previously Not Balanced)`."
function _suffixes(c)
    out = String[]
    c.gap && push!(out, "(Previous Gap Day)")
    c.waiting && push!(out, "(Awaiting Gap Day)")
    (!any(_kind_changed, c.shown) && !isempty(c.shown) && c.balance !== nothing) &&
        push!(out, "(Previously Not Balanced)")
    return out
end

"""
    _day_bullets(c) -> Vector{String}

What happened to the day, one line each. An entered day starts with its entry (and
how its differences were explained), then either the last same-session update or
every reported edit. A revised day starts with when it was first saved.
"""
function _day_bullets(c)
    items = String[]
    if c.entered
        push!(items, "$(_clock24(c.entry.when)) &ndash; entered and saved by $(_e(c.entry.who))" *
                     _explained(c.entry_diffs))
        c.again === nothing ||
            push!(items, "$(_clock24(c.again.when)) &ndash; updated by $(_e(c.again.who))")
    elseif c.seen !== nothing
        push!(items, "First saved on $(_hdash(c.seen)) at $(_clock24(c.seen))" *
                     (c.first_diffs === nothing ? "" : _explained(c.first_diffs)))
    end
    edits = isempty(c.shown) ? (!c.entered && c.latest !== nothing ? [c.latest] : Changes.Row[]) : c.shown
    for r in edits
        push!(items, "Changed on $(_hdash(r.when)) by $(_e(r.who)) at $(_clock24(r.when))" *
                     (isempty(_html_parts(r)) ? ", with no figure different" : ""))
    end
    return items
end

"""
    _ledger_made(io, released)

For each ledger a save let be made: `✓ Ledger made for 23 September 2026` in the
accent, and, when it came out with a difference, that difference on a small tag
row of its own with its explanation under it.
"""
function _ledger_made(io, released)
    for f in released
        println(io, "<div class=\"la\" style=\"margin-top:10px;font-size:14px;line-height:20px;font-weight:600;",
                    "color:#1F6F5C;\">&#10003; Ledger made for $(_hlong(f.day))</div>")
        tags = _diff_tags(f.diffs)
        isempty(tags) && continue
        println(io, "<div style=\"margin-top:4px;font-size:12px;line-height:20px;\">",
                    join((_pill(t, tone; small = true) for (t, tone) in tags), " "), "</div>")
        parts = Tuple{String,String}[]
        f.diffs.night === nothing || push!(parts, ("OB", f.diffs.night.reason))
        f.diffs.day === nothing   || push!(parts, ("CB", f.diffs.day.reason))
        for (w, r) in parts
            label = length(parts) == 1 ? "explanation" : "$(w) explanation"
            print(io, _soft(isempty(r) ? "no explanation given" : "$(label): $(_e_lines(r))", "2px"))
        end
    end
    return nothing
end

"""
    _day_card(io, c)

One day: a two-column table. On the left the date (with its suffixes) and the
bullets; on the right ONLY its tags, top-aligned and never wrapped, one above
another; and, across the whole card below, the ledgers the day released (one
more line after the bullets) and the change table of each reported edit.
"""
function _day_card(io, c)
    _card_open(io)
    println(io, _TABLE, ">")
    println(io, "<tr><td valign=\"top\" style=\"padding:0 8px 0 0;\">")
    suffix = replace(join(_suffixes(c), " "), " " => "&nbsp;")    # each word stays with its group
    suffix = replace(suffix, ")&nbsp;(" => ") (")
    println(io, "<div class=\"li\" style=\"font-size:15px;line-height:22px;font-weight:600;color:#1C2521;\">",
                _hlong(c.day), isempty(suffix) ? "" :
                " <span class=\"ls\" style=\"font-size:13px;font-weight:400;color:#5B6660;\">$(suffix)</span>", "</div>")
    print(io, _bullets(_day_bullets(c)))
    println(io, "</td><td valign=\"top\" align=\"right\" style=\"padding:0;white-space:nowrap;\">")
    for (i, (text, tone)) in enumerate(_tags(c))
        println(io, "<div style=\"margin-top:$(i == 1 ? 2 : 6)px;text-align:right;white-space:nowrap;\">", _pill(text, tone), "</div>")
    end
    println(io, "</td></tr>")
    if !isempty(c.released)
        # Across the card, under the bullets: the tags beside them would not fit a narrow screen.
        println(io, "<tr><td colspan=\"2\" style=\"padding:0;\">")
        _ledger_made(io, c.released)
        println(io, "</td></tr>")
    end
    tables = String[_edit_table(r; caption = length(c.shown) > 1) for r in c.shown]
    if any(!isempty, tables)
        println(io, "<tr><td colspan=\"2\" style=\"padding:0;\">")
        foreach(t -> print(io, t), tables)
        println(io, "</td></tr>")
    end
    println(io, "</table>")
    _card_close(io)
end

"""
    _waiting_section(io, waiting)

The last section: every saved day whose ledger cannot be made yet, in one card.
The date and what it is waiting for are one block with a real line break between
them (`<br>`, then a newline so that a converter that drops tags still has one).
"""
function _waiting_section(io, waiting::Vector{Date})
    _label(io, "Saved Days with Pending Ledgers", :accent)
    _card_open(io)
    for (i, d) in enumerate(waiting)
        f = _waiting_facts(d)
        rest = f.until === nothing ?
               "Saved, but its ledger has not been made yet. The day before it is already on record." :
               "Saved, but its ledger cannot be made until $(_long(f.until)) is entered."
        println(io, "<div class=\"lr\" style=\"$(i == 1 ? "" : _ROW_TOP)padding:$(i == 1 ? "0" : "10px") 0 10px;\">",
                    "<span class=\"li\" style=\"font-size:15px;line-height:22px;font-weight:700;color:#1C2521;\">",
                    "$(_hlong(d))</span><br>\n",
                    "<span class=\"ls\" style=\"font-size:14px;line-height:20px;color:#5B6660;\">$(_prose(rest))</span></div>")
    end
    print(io, _soft("This list clears automatically as gap dates are filled in.", "0px", 12))
    _card_close(io)
end

# --- The head of the message --------------------------------------------------

const _SPACER_PAIRS = repeat("&#8199;&#847;", 40)

# The title band's font size, as large as fits on ONE row (measured in Chrome with
# Segoe UI and with Arial, the wider of the two, with 5% in hand and the widest
# date; see handoff/email-html-round2.md and the revisions of
# handoff/email-html-design.md). The band has 16px of padding each side inside a
# 12px page margin, so the text has the viewport less 56px. `_HEADER_BASE` is the
# inline size, right for a 360px-wide phone and so for any app that drops the
# <style> block; the media rules below make it larger on wider screens and
# smaller under 360px. Capped at 28px. Each pair is ("Daily Report", "Corrected
# Report"), measured separately because the second wording is longer.
const _HEADER_BASE  = (18.5, 16.0)
const _HEADER_SMALL = (16.0, 14.0)                       # viewport under 360px
const _HEADER_STEPS = ((375, 19.5, 17.0), (390, 20.5, 17.5), (412, 21.5, 19.0),
                       (430, 23.0, 20.0), (600, 28.0, 28.0))   # (min viewport, daily, corrected)

_px(x::Real) = (isinteger(x) ? string(Int(x)) : string(x)) * "px"

"The media rules for the title band: `.lh` is the daily wording, `.lhc` the corrected one."
function _header_rules()
    io = IOBuffer()
    println(io, "@media screen and (max-width:359px){.lh{font-size:$(_px(_HEADER_SMALL[1]))!important}",
                ".lhc{font-size:$(_px(_HEADER_SMALL[2]))!important}}")
    for (w, a, b) in _HEADER_STEPS
        println(io, "@media screen and (min-width:$(w)px){.lh{font-size:$(_px(a))!important}",
                    ".lhc{font-size:$(_px(b))!important}}")
    end
    return String(take!(io))
end

const _HEAD_STYLE = """
:root{color-scheme:light dark;supported-color-schemes:light dark}
$(_header_rules())a[x-apple-data-detectors]{color:inherit!important;text-decoration:none!important}
@media (prefers-color-scheme:dark){
.lp{background-color:#121614!important}
.lband{background-color:#175649!important}
.lc{background-color:#1B211E!important;border-color:#2F3833!important}
.li{color:#E4E9E6!important}
.ls{color:#A2ACA6!important}
.la{color:#7CC8B0!important}
.lb{background-color:#17322A!important}
.ld{color:#F2A0A2!important}
.ldb{background-color:#3A2022!important;border-color:#5A3033!important}
.lw{color:#E8BF6A!important}
.lwb{background-color:#372C15!important}
.lq{background-color:#252C28!important}
.lr{border-color:#2F3833!important}
.lsd{border-left-color:#F2A0A2!important}
}
"""

"""
    _title_band(to, corrected) -> String

`LDGR | Daily Report | 23-09-2026` (or `Corrected Report`): white on a full-width
green band with the cards' rounded corners. Every piece carries its colour, so the
white text can never fall on no fill; the band's own fill is set twice.
"""
function _title_band(to::DateTime, corrected::Bool)
    cls = corrected ? "lhc" : "lh"
    size = _HEADER_BASE[corrected ? 2 : 1]
    pipe = "<span style=\"color:#B9D9CE;\"> | </span>"
    return "<tr><td class=\"lband\" bgcolor=\"#1F6F5C\" style=\"background-color:#1F6F5C;border-radius:12px;padding:12px 16px;\">" *
           "<div class=\"$(cls)\" style=\"font-size:$(_px(size));line-height:1.3;white-space:nowrap;color:#FFFFFF;\">" *
           "<span style=\"color:#FFFFFF;font-weight:700;\">LDGR</span>$(pipe)" *
           "<span style=\"color:#FFFFFF;font-weight:600;\">$(corrected ? "Corrected Report" : "Daily Report")</span>$(pipe)" *
           "<span style=\"color:#FFFFFF;font-weight:600;\">$(_hdash(to))</span></div></td></tr>\n"
end

"""
    _html_note(note) -> String

A note as the HTML says it, or `""`. The LATE sentence is dropped (the title and
the caption already say what the report covers; the owner does not want the
apology), and so is the several-days paragraph (it is not passed here at all). The
rest — corrected, follow-up, possible repeat, first report, clock — stay.
"""
_html_note(note::AbstractString) = String(strip(replace(String(note), r"This report is late:[^.]*\.\s*" => "")))

"""
    _preheader(plan, ...) -> String

The hidden line a phone shows after the subject. An unreadable log says so
first, because it is what must never be missed; a quiet report says what the
text says; otherwise it is the counts, and up to two of the differences, worded
as the tags are.
"""
function _preheader(plan, problem::AbstractString, span::Bool, has_rows::Bool, order, cards)
    if !isempty(problem)
        return _prose(_UNREAD_LEAD * " so this report may be missing entries. It is not a quiet day.")
    end
    quiet = plan.n_entered == 0 && plan.n_changed == 0 && plan.n_waiting == 0
    quiet && return _prose(_quiet_text(span, has_rows))
    line = join((last(p) for p in _summary_parts(plan.n_entered, plan.n_diff, plan.n_changed, plan.n_waiting)), " · ")
    found = String[]
    for d in order
        c = cards[d]
        (c.diffs === nothing || c.state === :off) || _difference_sentences!(found, d, c.diffs)
        for r in c.released
            _difference_sentences!(found, r.day, r.diffs)
        end
    end
    isempty(found) || (line *= " — " * join(first(found, 2), " "))
    return _prose(line)
end

"Add `CB Shortage (\$2,000.00) on 29 September.` for each difference on a day, the opening first."
function _difference_sentences!(out::Vector{String}, d::Date, f)
    for (text, _) in _diff_tags(f)
        push!(out, "$(text) on $(_short(d)).")
    end
    return out
end

"""
    _html_body(plan, rows, problem, from, to; note, corrected, subject) -> String

The whole HTML document, top to bottom: the hidden preheader, the title band, the
caption saying how current the report is, the notes (plain, in parentheses), the
DAYS ENTERED section — one card for every day, newest first — then, only when the
change log could not be read, the red warning, then SAVED DAYS WITH PENDING
LEDGERS, always last, and the footer.
"""
function _html_body(plan, rows::Vector{Changes.Row}, problem::AbstractString,
                    from::Union{Nothing,DateTime}, to::DateTime;
                    note::AbstractString = "", corrected::Bool = false, subject::AbstractString = "")
    (; waiting, entered, gaps, changed, n_entered, n_changed, n_waiting) = plan
    quiet  = n_entered == 0 && n_changed == 0 && n_waiting == 0
    span   = _spans(from, to)
    unread = !isempty(problem)

    order = sort(vcat(entered, gaps, changed); rev = true)
    cards = Dict{Date,Any}(d => _card_facts(d, plan) for d in order)

    io = IOBuffer()
    println(io, "<!DOCTYPE html>")
    println(io, "<html lang=\"en\">")
    println(io, "<head>")
    println(io, "<meta charset=\"utf-8\">")
    println(io, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
    println(io, "<meta name=\"x-apple-disable-message-reformatting\">")
    println(io, "<meta name=\"format-detection\" content=\"telephone=no, date=no, address=no, email=no\">")
    println(io, "<meta name=\"color-scheme\" content=\"light dark\">")
    println(io, "<meta name=\"supported-color-schemes\" content=\"light dark\">")
    println(io, "<title>$(_e(subject))</title>")
    println(io, "<style>")
    print(io, _HEAD_STYLE)
    println(io, "</style>")
    println(io, "</head>")
    println(io, "<body class=\"lp\" bgcolor=\"#FAF9F6\" style=\"margin:0;padding:0;background-color:#FAF9F6;",
                "-webkit-text-size-adjust:100%;\">")
    println(io, "<div style=\"display:none;max-height:0;max-width:0;overflow:hidden;opacity:0;mso-hide:all;",
                "font-size:1px;line-height:1px;color:#FAF9F6;\">",
                _preheader(plan, problem, span, !isempty(rows), order, cards), "</div>")
    println(io, "<div style=\"display:none;max-height:0;overflow:hidden;mso-hide:all;\">", _SPACER_PAIRS, "</div>")
    println(io, "<table role=\"presentation\" class=\"lp\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" ",
                "border=\"0\" bgcolor=\"#FAF9F6\" style=\"background-color:#FAF9F6;\">")
    println(io, "<tr><td align=\"center\" style=\"padding:24px 12px 32px;\">")
    println(io, "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" border=\"0\" ",
                "style=\"max-width:600px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,",
                "Helvetica,Arial,sans-serif;\">")

    # The title band, the very first thing seen.
    print(io, _title_band(to, corrected))

    # The caption, then the notes: soft text, no box.
    lines = String[]
    if !isempty(rows)
        latest = maximum(r -> r.when, rows)
        push!(lines, _soft(_prose("Includes everything saved up to $(_clock24(latest)) on $(_short(Date(latest)))."),
                           _lines_margin(lines)))
    end
    html_note = _html_note(note)
    isempty(html_note) || push!(lines, _soft("(" * _prose24(html_note) * ")", _lines_margin(lines)))
    if !isempty(lines)
        println(io, "<tr><td style=\"padding:0 4px;\">")
        foreach(l -> print(io, l), lines)
        println(io, "</td></tr>")
    end

    # A quiet report says so, in a card. Never an all-clear beside a log that could
    # not be read.
    if quiet && !unread
        print(io, _SPACER16)
        mark = isempty(rows) ? "<span class=\"la\" style=\"color:#1F6F5C;font-weight:700;\">&#10003;</span> " : ""
        println(io, "<tr><td class=\"lc\" bgcolor=\"#FFFFFF\" style=\"$(_CARD_STYLE)border-radius:12px;padding:14px 18px;\">",
                    "<div class=\"li\" style=\"font-size:16px;line-height:24px;font-weight:600;color:#1C2521;\">",
                    mark, _prose(_quiet_text(span, !isempty(rows))), "</div></td></tr>")
    end

    # The days.
    if !isempty(order)
        _label(io, "Days entered", :accent)
        cs = String[]
        for d in order
            b = IOBuffer()
            _day_card(b, cards[d])
            push!(cs, String(take!(b)))
        end
        print(io, join(cs, _SPACER))
    end

    # The unreadable-log warning, right after the days.
    if unread
        print(io, _SPACER16)
        println(io, "<tr><td class=\"ldb lsd\" bgcolor=\"#FBEDE9\" style=\"background-color:#FBEDE9;border:1px solid #E9C3BE;",
                    "border-left:4px solid #A63D40;border-radius:12px;padding:14px 18px;\">",
                    "<div class=\"li\" style=\"font-size:14px;line-height:21px;color:#1C2521;\">",
                    "<strong class=\"ld\" style=\"color:#A63D40;\">$(_e(_UNREAD_LEAD))</strong>",
                    _prose(_unread_rest(problem)), "</div></td></tr>")
    end

    # The ledgers still waiting: always the last section.
    isempty(waiting) || _waiting_section(io, waiting)

    # Footer: the credit the form shows (public/index.html, `.watermark`), as text;
    # mail apps drop the sun icon. The Records folder line is the text's alone.
    println(io, "<tr><td style=\"padding:28px 4px 0;\">")
    println(io, "<div class=\"ls lr\" align=\"center\" style=\"border-top:1px solid #E3E0D8;padding-top:14px;",
                "font-size:12px;line-height:18px;color:#5B6660;text-align:center;\">",
                "Powered by <b style=\"font-weight:600;\">SolRegia</b></div>")
    println(io, "</td></tr>")
    println(io, "</table>")
    println(io, "</td></tr></table>")
    println(io, "</body>")
    println(io, "</html>")
    return String(take!(io))
end

"The top margin of the next caption or note line: none for the first, 4px for the rest."
_lines_margin(lines::Vector{String}) = isempty(lines) ? "10px" : "4px"
