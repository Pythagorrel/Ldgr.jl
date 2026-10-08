module Checks

using Dates
using ..Config
using ..DayInput

# =============================================================================
# CHECKS — every warning the program can raise, in one place.
#
# ENTIRELY NEW IN v4.0. This module is the whole point of the version.
#
# WHAT CHANGED PHILOSOPHICALLY: v3.0 recorded what it was given and raised one
# warning (negative undeposited funds, buried in Ledger.jl). v4.0 subjects the
# day to a graded battery of checks before anything is written. The tiers below
# correspond one-to-one with the "ldgr Warnings Guide" document; the code on
# each Finding (L1-A, L2-B, ...) is the section heading in that document, so a
# warning on screen can always be traced to a written explanation.
#
# THE FOUR LEVELS (Warnings Guide §2). These are not decoration — they decide
# whether the day can be saved at all:
#
#   1 STOP     Physically impossible. Blocks saving. There is no honest reason
#              to record a day where more cash left the drawer than was ever in
#              it, so refusing costs nothing.
#   2 EXPLAIN  Possible, but unaccounted for. ALLOWS saving, requires a typed
#              reason. This is deliberate and is the single most important
#              design decision in the module: refusing to record a real
#              discrepancy does not make it go away, it pushes the operator to
#              adjust a figure until the day fits, and then the error is
#              invisible forever. A flagged day is honest and fixable; a
#              plugged day is neither.
#   3 NOTICE   Nothing is wrong; something is pending or needs confirming.
#   4 HINT     A guess at what caused a difference. Advice only, never blocks,
#              and is sometimes wrong.
#
# WHY THE CHECKS LIVE HERE AND NOT IN server.jl OR app.js: Handover §4 rule 5 —
# the browser validates only so the user gets instant feedback; it is not
# authoritative. Every rule has to exist server-side too, and the way two
# copies of a rule stay in step is by there only being one copy. The server
# calls this module; the browser is told what this module said.
#
# WHAT THIS MODULE DELIBERATELY DOES NOT DO: it does not write anything, it
# does not read files, and it does not decide what happens next. It takes a day
# (and optionally the day before it) and returns a list of findings. The caller
# decides whether to block, prompt, or post. That is what makes it testable in
# isolation and what stops validation logic leaking into the driver.
# =============================================================================

export Finding, LEVEL_STOP, LEVEL_EXPLAIN, LEVEL_NOTICE, LEVEL_HINT,
       level_name, finding_title, check_day, has_stops, stops, needs_reason,
       reason_for, unexplained,
       day_residual, overnight_variance, predicted_closing,
       identity_inflow, identity_outflow, MONEY_TOL, is_zero_money

const LEVEL_STOP    = 1
const LEVEL_EXPLAIN = 2
const LEVEL_NOTICE  = 3
const LEVEL_HINT    = 4

level_name(l::Int) = l == LEVEL_STOP    ? "STOP" :
                     l == LEVEL_EXPLAIN ? "EXPLAIN" :
                     l == LEVEL_NOTICE  ? "NOTICE" : "HINT"

# --- Short titles -----------------------------------------------------------
# A few plain words for each code, e.g. "Day doesn't balance" for L2-A.
#
# WHY THEY EXIST: the entry form lists the day's warnings in a side panel, one
# row each, and a column of full paragraphs cannot be taken in at a glance. A
# title is only the label on that row. The full `message` is still the
# explanation, and the code still traces the warning back to its section of
# the Warnings Guide; the title replaces neither. It lives here rather than in
# app.js for the same reason the checks do: the browser shows what this module
# says and holds no warning wording of its own.
#
# An unknown code gets "" rather than an error, so a missing title can never
# stop the warning itself from reaching the screen. When adding a code, add its
# title too: test_checks_titles.jl fails for any code raised in this file that
# has none.
#
# The codes themselves are never shown on the form. They are for the audit log,
# the tests and whoever maintains this file, not for the people entering days.
const FINDING_TITLES = Dict{String,String}(
    "L1-A" => "Negative amount",
    "L1-B" => "Expenses exceed total cash",
    "L1-C" => "Balance Not Entered",          # the form names the box: see finding_title(::Finding)
    "L1-D" => "Not a valid amount",
    "L1-E" => "Date not allowed",
    "L2-A" => "Day doesn't balance",
    "L2-B" => "Opening doesn't match last close",
    "L3-A" => "Ledger waiting on the day before",
    "L3-B" => "Day saved, ledger generated",
    "L3-C" => "Marked as closed",
    "L3-D" => "First day on record",
    "L3-E" => "Day after already on record",
    "L4-1" => "Digits may be swapped",
    "L4-2" => "Matches one of your figures",
    "L4-3" => "Decimal point may be off",
    "L4-4" => "Card and cash may be mixed up",
)

"""
    finding_title(code) -> String

The short title for a Warnings Guide code, or `""` for a code not in the table.
"""
finding_title(code::AbstractString) = get(FINDING_TITLES, code, "")

"""
    Finding

One thing the program has to say about a day.

  code    the Warnings Guide section, e.g. "L2-A". Never invent a new code
          without adding the matching section to the document — the code is a
          promise that an explanation exists.
  level   1..4, as above.
  field   which input this concerns, or `nothing` for whole-day findings. The
          UI uses this to put the message next to the offending box rather
          than only at the bottom of the form (Warnings Guide §8).
  message plain English, addressed to a non-accountant.
  amount  the figure involved, where there is one, so the UI can format it as
          money rather than parsing it back out of the message text.
"""
struct Finding
    code::String
    level::Int
    field::Union{Nothing,Symbol}
    message::String
    amount::Union{Nothing,Float64}
end
Finding(code, level, field, message) = Finding(code, level, field, message, nothing)

"""
    finding_title(f::Finding) -> String

The title for one finding. A balance left blank (L1-C) is titled after its own
box, "Opening Balance Not Entered" or "Closing Balance Not Entered", because the
same code covers both boxes and the row should say which one without making
anyone read the explanation. Every other finding takes its code's title.
"""
function finding_title(f::Finding)
    f.code == "L1-C" && f.field !== nothing && return "$(label_of(f.field)) Not Entered"
    return finding_title(f.code)
end

# --- Money comparison -------------------------------------------------------
# Cash is decimal, Float64 is binary, and 0.1 + 0.2 != 0.3 in binary. Comparing
# a residual to exactly 0.0 would therefore raise a phantom half-cent
# discrepancy on perfectly good days. Half a cent is below the smallest coin in
# circulation, so anything under it is treated as zero.
const MONEY_TOL = 0.005
is_zero_money(x::Real) = !isnan(x) && abs(x) < MONEY_TOL

"""
    money(x)

Format an amount the way it appears on the sheet: \$1,270.00.

Written by hand rather than pulled from a formatting package because these
strings go straight into warnings a non-accountant reads, and "\$222400.0" in a
warning about missing money is the kind of thing that makes someone distrust
the whole message. Works in integer cents throughout so that a value like
1269.999999 cannot round to "\$1,269.100".
"""
function money(x::Real)
    isnan(x) && return "(not counted)"
    total_cents = round(Int, abs(x) * 100)
    whole, cents = divrem(total_cents, 100)
    s = string(whole)
    grouped = ""
    while length(s) > 3                       # insert a comma every three digits
        grouped = "," * s[end-2:end] * grouped
        s = s[1:end-3]
    end
    return "\$" * s * grouped * "." * lpad(cents, 2, '0')
end

"""
    spoken_date(d)

A date the way the form says it out loud: 14 September 2026.

Here for the same reason `money` is: a message a non-accountant reads should not
switch between "12 September 2026" in one sentence and "2026-09-12" in the next.
Deliberately NOT exported and deliberately not borrowed from server.jl — the
checks may not depend on the web layer, and server.jl has the identical one
line for what it says in its own replies.
"""
spoken_date(d::Date) = Dates.format(d, "d U yyyy")

# ---------------------------------------------------------------------------
# The identity itself (Warnings Guide §1)
# ---------------------------------------------------------------------------
# Opening + Cash sales − Expenses − Deposit − Mr. Boyle = Closing
#
# The key lists come from Config so that adding an expense category joins the
# identity automatically. Note again what is absent: the three POS keys. Card
# money settles bank-side and never enters the drawer, so it belongs to neither
# side of this equation. Nothing in this program can check a POS figure.

"Sum of the categories that put physical cash INTO the drawer."
identity_inflow(rec::DayRecord) = sum(rec.amounts[k] for k in IDENTITY_INFLOW_KEYS; init=0.0)

"Sum of the categories that take physical cash OUT of the drawer."
identity_outflow(rec::DayRecord) = sum(rec.amounts[k] for k in IDENTITY_OUTFLOW_KEYS; init=0.0)

"The cash there was to pay out of: the opening balance plus the cash that came in."
cash_available(rec::DayRecord) = rec.amounts[:opening_balance] + identity_inflow(rec)

"What the day's figures say should be in the drawer at close."
predicted_closing(rec::DayRecord) =
    rec.amounts[:opening_balance] + identity_inflow(rec) - identity_outflow(rec)

"""
    day_residual(rec)

Counted closing minus predicted closing. Warnings Guide L2-A.

  positive → SURPLUS: more cash in the drawer than the books explain.
  negative → SHORTAGE: the books claim cash that is not there.

Returns NaN if either balance was never counted, which is why L1-C has to run
first — NaN deliberately poisons rather than reading as a plausible zero.
"""
day_residual(rec::DayRecord) = rec.amounts[:closing_balance] - predicted_closing(rec)

"""
    overnight_variance(rec, prior_closing)

Typed opening minus the previous working day's closing. Warnings Guide L2-B.

SIGN CONVENTION, FIXED HERE AND NOWHERE ELSE: `entered − prior`, so negative
means a shortage, matching day_residual. A variance column whose sign gets
inverted somewhere is nearly impossible to spot, because both signs look
plausible on the page. Every consumer must use this function rather than
subtracting by hand.

The variance is attributed to THIS day — the later of the two — because that
is the day it is discovered and the day someone can still act on it.
"""
overnight_variance(rec::DayRecord, prior_closing::Float64) =
    rec.amounts[:opening_balance] - prior_closing

# No previous day on record — a gap, or the first day ever. There is nothing to
# compare against, so the variance is not zero in the sense of "checked and
# found equal"; it is simply not computable. Zero is the right value to store
# because it must not post a phantom row to Cash Over/Short, and the fact that
# no comparison happened is already reported separately as L3-A (ledger held) or
# L3-D (genesis). This method exists so that a missing prior day is an ordinary
# case rather than an error the caller has to guard every call site against.
overnight_variance(::DayRecord, ::Nothing) = 0.0

# ---------------------------------------------------------------------------
# TIER 0 / LEVEL 1 — STOP (Warnings Guide §3)
# ---------------------------------------------------------------------------
"""
    stop_checks(rec) -> Vector{Finding}

Everything that describes a state which cannot physically have existed.

These run before anything else and, if any fires, the caller must not save the
day. They are also the only checks with no override path anywhere in the
system — see needs_reason below.
"""
function stop_checks(rec::DayRecord)
    out = Finding[]

    # --- L1-A: a negative figure -------------------------------------------
    # Every field is a QUANTITY of cash. A negative would mean money flowing
    # the opposite way, which is a different transaction in a different
    # direction and belongs in its own field: a refund, a withdrawal from the
    # bank into the till, money in from Mr. Boyle. None of those fields exist
    # yet (Warnings Guide L1-A note, and Handover §7 "Cash Refund to
    # Customers"). Allowing a minus sign as a shortcut would net two opposite
    # transactions into one figure, which flips the debit/credit side in the
    # ledger and produces a wrong row even when the total looks right.
    for k in JOURNAL_KEYS
        v = rec.amounts[k]
        if !isnan(v) && v < 0.0
            push!(out, Finding("L1-A", LEVEL_STOP, k,
                "\"$(label_of(k))\" cannot be negative. If money moved the other way, " *
                "that is a different kind of transaction and needs its own field — " *
                "please raise it rather than entering a minus figure.", v))
        end
    end

    # --- L1-D: a figure that is not usable money ---------------------------
    # Reached when a value survives parsing but is not a real number (Inf, NaN
    # arriving in a posted category), or carries sub-cent precision that no
    # cash drawer can hold. Cash book NaN is EXCLUDED here because that is the
    # legitimate NOT_COUNTED sentinel and is L1-C's job, not this one.
    for k in JOURNAL_KEYS
        v = rec.amounts[k]
        if k in CASH_BOOK_KEYS && isnan(v)
            continue                                   # handled by L1-C
        elseif isnan(v) || isinf(v)
            push!(out, Finding("L1-D", LEVEL_STOP, k,
                "\"$(label_of(k))\" is not a usable number.", nothing))
        elseif abs(v - round(v, digits=2)) > 1e-9
            push!(out, Finding("L1-D", LEVEL_STOP, k,
                "\"$(label_of(k))\" has more than two decimal places. " *
                "Cash cannot be smaller than a cent.", v))
        end
    end

    # --- L1-E: a date that has not happened yet ----------------------------
    if rec.date > Dates.today()
        push!(out, Finding("L1-E", LEVEL_STOP, :date,
            "$(rec.date) is in the future. Nobody has counted that day's drawer yet.", nothing))
    end
    if year(rec.date) < 2000
        push!(out, Finding("L1-E", LEVEL_STOP, :date,
            "$(rec.date) is too far in the past to be a real entry.", nothing))
    end

    # A closed day has no balances of its own to check — they are carried
    # through from the previous working day by the caller — so the two checks
    # below do not apply to it. See Warnings Guide L3-C: nobody counts the
    # drawer on a Sunday, so asking for a figure would invite a fiction.
    if is_closed(rec)
        return out
    end

    # --- L1-C: a balance that was never counted ----------------------------
    # The distinction this check exists to protect is subtle and the single
    # easiest thing in the system to get wrong: blank means "nobody looked",
    # zero means "somebody looked and it was empty". Only one of those is an
    # assertion. Handover §4 rule 6 makes blank become zero at the input
    # boundary, which is right for every posted category and wrong for these
    # two — hence the NOT_COUNTED sentinel in DayInput.
    for k in CASH_BOOK_KEYS
        if not_counted(rec.amounts[k])
            push!(out, Finding("L1-C", LEVEL_STOP, k,
                "\"$(label_of(k))\" has not been filled in. Blank is not the same as zero here. " *
                "Enter 0 only if it really was empty.", nothing))
        end
    end

    # --- L1-B: more cash left than was ever there --------------------------
    # Only computable once the balances are known, so it sits after L1-C and is
    # skipped if either balance is missing (the guard below), otherwise it
    # would compare against NaN and never fire.
    o = rec.amounts[:opening_balance]
    if !not_counted(o)
        available = cash_available(rec)
        outflow   = identity_outflow(rec)
        if outflow - available > MONEY_TOL
            push!(out, Finding("L1-B", LEVEL_STOP, nothing,
                "Expenses, deposits and Mr. Boyle come to $(money(outflow)), " *
                "but only $(money(available)) was available " *
                "(opening $(money(o)) plus cash sales $(money(identity_inflow(rec)))).",
                outflow - available))
        end
    end

    # A negative counted closing balance. Usually implied by L1-B, but caught
    # separately because it can also arrive from a mistyped balance on a day
    # whose outflows are perfectly fine.
    c = rec.amounts[:closing_balance]
    if !not_counted(c) && c < 0.0
        push!(out, Finding("L1-B", LEVEL_STOP, :closing_balance,
            "A drawer cannot hold a negative amount of cash.", c))
    end

    return out
end

# ---------------------------------------------------------------------------
# TIER 1 & 2 / LEVEL 2 — EXPLAIN (Warnings Guide §4)
# ---------------------------------------------------------------------------
"""
    balance_checks(rec, prior_closing) -> Vector{Finding}

The two checks that matter most. Both mean money is unaccounted for, both
allow the day to be saved, and each requires its own typed reason (see
reason_for).

`prior_closing` is `nothing` when there is no previous day on record — either
this is the first day ever, or there is a gap. The overnight check is then
simply not computable and is skipped here; the caller raises L3-A or L3-D
instead. That is the whole gap-handling story: not an error state, just
arithmetic waiting on an input.
"""
function balance_checks(rec::DayRecord, prior_closing::Union{Nothing,Float64})
    out = Finding[]
    is_closed(rec) && return out          # a closed day has no figures to check

    # --- L2-A: the day does not balance ------------------------------------
    d = day_residual(rec)
    if !isnan(d) && !is_zero_money(d)
        push!(out, Finding("L2-A", LEVEL_EXPLAIN, :closing_balance,
            "The day does not balance. The figures predict $(money(predicted_closing(rec))) " *
            "and $(money(rec.amounts[:closing_balance])) was counted.", d))
    end

    append!(out, overnight_checks(rec, prior_closing))
    return out
end

"""
    overnight_checks(rec, prior_closing) -> Vector{Finding}

L2-B on its own: does this morning's opening balance match the last close?

Split out of balance_checks because it needs nothing else from the day, so
check_day can run it while a Stop about some other box holds the rest back.
"""
function overnight_checks(rec::DayRecord, prior_closing::Union{Nothing,Float64})
    out = Finding[]
    (is_closed(rec) || prior_closing === nothing) && return out

    # --- L2-B: this morning does not match last night ----------------------
    v = overnight_variance(rec, prior_closing)
    if !isnan(v) && !is_zero_money(v)
        word = v > 0 ? "more" : "less"
        push!(out, Finding("L2-B", LEVEL_EXPLAIN, :opening_balance,
            "The opening balance does not match the last working day. " *
            "It is $(money(v)) $word than the $(money(prior_closing)) that day closed with. " *
            "The day's own arithmetic still uses the figure that was counted this morning.", v))
    end
    return out
end

# ---------------------------------------------------------------------------
# TIER 6 / LEVEL 4 — HINTS (Warnings Guide §6)
# ---------------------------------------------------------------------------
"""
    hint_checks(rec, findings) -> Vector{Finding}

Given a difference, guess what caused it.

This is the most useful thing on the screen for someone who is not an
accountant, because it turns "you are \$450 out" into something they can go and
check. Every hint here is a heuristic and any of them can be wrong; they are
suggestions attached to a warning, never a diagnosis and never blocking.

Only runs when there is a difference to explain, so a clean day produces no
hints at all.
"""
function hint_checks(rec::DayRecord, findings::Vector{Finding})
    out = Finding[]

    diffs = [f.amount for f in findings
             if f.level == LEVEL_EXPLAIN && f.amount !== nothing && !isnan(f.amount)]
    isempty(diffs) && return out

    # Every figure the operator actually typed, for comparison against the gap.
    typed = Dict{Symbol,Float64}(k => rec.amounts[k] for k in JOURNAL_KEYS
                                 if !isnan(rec.amounts[k]) && rec.amounts[k] > MONEY_TOL)

    for raw in diffs
        d = abs(round(raw, digits=2))
        d < MONEY_TOL && continue

        # --- Divisible by 9 → digits in the wrong place --------------------
        # The classic bookkeeping tell. Swapping two digits, or moving a
        # decimal point, always leaves a difference that is a multiple of 9
        # (2,720 for 2,270 leaves 450; 450 / 9 = 50). It cannot say WHICH
        # figure, only that the shape of the error is a misplaced digit.
        cents = round(Int, d * 100)
        if cents % 9 == 0
            push!(out, Finding("L4-1", LEVEL_HINT, nothing,
                "$(money(d)) divides evenly by 9, which usually means two digits are " *
                "swapped or a decimal point is in the wrong place.", d))
        end

        for (k, v) in typed
            # --- Difference equals a figure exactly ------------------------
            if abs(d - v) < MONEY_TOL
                push!(out, Finding("L4-2", LEVEL_HINT, k,
                    "The difference is exactly \"$(label_of(k))\" ($(money(v))). " *
                    "That figure may have been entered twice, or missed out somewhere.", v))
            end
            # --- Difference is 9x a figure → decimal slip on that figure ---
            # 7,500 typed where 75,000 belonged leaves 67,500, which is 9 × 7,500.
            if abs(d - 9v) < MONEY_TOL
                push!(out, Finding("L4-3", LEVEL_HINT, k,
                    "The difference is exactly nine times \"$(label_of(k))\" ($(money(v))). " *
                    "That figure probably has its decimal point in the wrong place.", v))
            end
        end

        # --- Difference equals the POS total or one of its parts -----------
        # Card money typed into cash sales, or cash typed into a POS box. This
        # is the one place a POS figure is checkable at all, and only
        # indirectly. See Warnings Guide §1.
        pos_keys = [c.key for c in cash_eq_in if c.key != :cash_sales]
        pos_total = sum(rec.amounts[k] for k in pos_keys; init=0.0)
        if pos_total > MONEY_TOL && abs(d - pos_total) < MONEY_TOL
            push!(out, Finding("L4-4", LEVEL_HINT, nothing,
                "The difference is exactly the total of the card takings ($(money(pos_total))). " *
                "Card money may have been entered as cash, or the other way round.", pos_total))
        end
    end

    # De-duplicate: the same hint can be produced by both differences on a day
    # where the opening and the closing are each wrong.
    seen = Set{Tuple{String,Union{Nothing,Symbol},String}}()
    uniq = Finding[]
    for f in out
        kk = (f.code, f.field, f.message)
        kk in seen && continue
        push!(seen, kk)
        push!(uniq, f)
    end
    return uniq
end

# ---------------------------------------------------------------------------
# The public entry point
# ---------------------------------------------------------------------------
"""
    check_day(rec; prior_closing, prior_date, is_genesis, ledger_exists,
                   in_books, next_in_books, next_date) -> Vector{Finding}

Run every applicable check against one day and return everything found, sorted
by severity.

  prior_closing   closing balance of the previous day on record, or `nothing`
                  if there is no previous day (gap, or first day ever).
  prior_date      the date that closing came from, used only in messages so the
                  operator can see WHICH day is being compared against.
  is_genesis      true when nothing but Off days is on record before this date,
                  so it would be the very first day. Suppresses L3-A; raises
                  L3-D while a Work day is not in the books yet (an Off day is
                  never the starting point).
  ledger_exists   true when a daily ledger file already exists for this date,
                  which means it may already be inside QuickBooks.
  in_books        true when this date already has a journal row.
  next_in_books   true when a Work day after this one already has a journal row
                  with only saved Off days in between, so this entry is filling
                  a gap underneath it (L3-E).
  next_date       that Work day, which L3-E names. Defaults to the day after.

THE TWO "IS IT ON RECORD" FACTS ARE PASSED IN, NOT LOOKED UP. This module reads
no files (see the header), so the caller hands it what the books say. Both
default to false, which is the right answer for a day being typed for the first
time and keeps every existing call site valid.

ORDER OF EVALUATION MATTERS. The stop checks run first and, if any fires, the
balance and hint checks are skipped: on a day with an uncounted closing balance
the residual is NaN, and reporting a NaN discrepancy on top of "you have not
filled this in" is noise, not information.

The one exception is the overnight check (L2-B). It needs only the opening
balance and the last close, so it still runs unless a Stop is about the opening
balance itself or the date. That is what lets the form ask why the opening
doesn't match as soon as it is entered, rather than only once the closing
balance is in at the end of the day.
"""
function check_day(rec::DayRecord;
                   prior_closing::Union{Nothing,Float64}=nothing,
                   prior_date::Union{Nothing,Date}=nothing,
                   is_genesis::Bool=false,
                   ledger_exists::Bool=false,
                   in_books::Bool=false,
                   next_in_books::Bool=false,
                   next_date::Date=rec.date + Day(1))

    findings = stop_checks(rec)

    if isempty(findings)
        append!(findings, balance_checks(rec, prior_closing))
        append!(findings, hint_checks(rec, findings))
    elseif !any(f -> f.field in (:opening_balance, :date), findings)
        # A Stop about some other box, most often a closing balance not entered
        # yet, says nothing about the opening balance or the last close.
        append!(findings, overnight_checks(rec, prior_closing))
    end

    # --- L3-D: the first day ever ------------------------------------------
    # The chain has to start somewhere. This opening balance cannot be checked
    # against anything and is accepted on trust, once, deliberately — and the
    # caller records that authorisation in the audit log. Without this the
    # gating rule below would hold the very first ledger forever and nothing
    # would ever post.
    #
    # GATED ON NO STOP. When a Stop has fired the day is refused outright, so
    # "the day itself is saved" (L3-A) or "accepted as the starting point"
    # (L3-D) would be false — the day was NOT saved. Showing both side by
    # side would tell the operator two contradictory things. The Stop already
    # explains why the day is blocked; the notice will appear cleanly on the
    # next attempt once the blocking problem is corrected.
    if !has_stops(findings)
        if is_genesis
            # ASKED ONCE, AND ONLY ONCE. A date that already has a journal row
            # got into the books either by being accepted as the starting point
            # or by having a day before it, so the question has been answered
            # and putting it again would ask the operator to re-authorise a
            # decision that is already recorded in the audit log. The date is
            # still the first day on record, which is why is_genesis stays true
            # and L3-A below stays suppressed. An Off day is never the starting
            # point: it is saved without the question (Chain.is_genesis_date).
            if !in_books && !is_closed(rec)
                push!(findings, Finding("L3-D", LEVEL_NOTICE, :opening_balance,
                    "This is the first day on record, so there is nothing to check the opening " *
                    "balance against. It will be accepted as the starting point for every day " *
                    "that follows.", nothing))
            end

        # --- L3-A: ledger held, waiting on the previous day ----------------
        # NOT an objection to a gap and NOT a calendar check — the program has
        # no idea which days it "should" have. The overnight difference is part
        # of this day's ledger, so without the previous day that ledger
        # genuinely cannot be finished. Arithmetic waiting on an input,
        # nothing more.
        #
        # Blast radius is exactly one day: the gate needs the previous day's
        # JOURNAL ROW, not its ledger. So a hole holds up the day after it and
        # nothing else — the rest of the month posts normally.
        elseif prior_closing === nothing && !is_closed(rec)
            push!(findings, Finding("L3-A", LEVEL_NOTICE, nothing,
                "The day before this one has not been entered yet, so this day's ledger " *
                "cannot be finished. The day itself is saved. The ledger will be produced " *
                "automatically once the missing day is entered.", nothing))
        end

        # --- L3-E: the day after this one is already on record ---------------
        # This entry is filling a gap. The day above it was saved with its
        # ledger held, waiting on exactly this day, and saving this one releases
        # it — with that day's overnight difference computed for the first time,
        # against the closing balance being typed here. So this closing count is
        # the figure the released day is about to be measured against, and the
        # person holding the count sheet is the only one in a position to notice
        # that the two mornings do not agree.
        #
        # It is a NOTICE, not a difference: nothing is wrong, and the program is
        # not asking for anything to be changed. Attached to the closing balance
        # because that is the figure it concerns. Raised for an Off day too, as
        # the carried balance is what the next morning is compared with.
        #
        # Not raised once this date has a row of its own: the release has already
        # happened, or was refused, and either way there is nothing pending on
        # this entry. Gated on no Stop for the same reason as L3-A and L3-D — a
        # refused day releases nothing.
        if next_in_books && !in_books
            push!(findings, Finding("L3-E", LEVEL_NOTICE, :closing_balance,
                "$(spoken_date(next_date)) is already on record and was waiting on " *
                "this day. Check that its opening balance matches this closing balance. " *
                "If they do not agree, that day will need an opening reason before its " *
                "ledger can be made.", nothing))
        end
    end

    # --- L3-B: a ledger already exists for this date ------------------------
    # The form regenerates the day's ledger file on every save; the replace
    # tick box was removed on 2026-09-29 at the owner's request. ldgr cannot
    # see inside QuickBooks, so this notice tells staff how to keep a
    # re-import from counting the day twice. The command line still needs
    # --force to overwrite a daily ledger.
    if ledger_exists
        push!(findings, Finding("L3-B", LEVEL_NOTICE, nothing,
            "A ledger has already been generated for $(spoken_date(rec.date)). " *
            "Before importing into QuickBooks, confirm that no journal already exists for this date. " *
            "If there is a QB journal already, delete that journal before importing a new one " *
            "with updated numbers and/or accounts. " *
            "If the numbers match, there is no need to change the QB records.", nothing))
    end

    # --- L3-C: closed day ---------------------------------------------------
    if is_closed(rec)
        carried = prior_closing === nothing ? "the previous working day's balance" : money(prior_closing)
        push!(findings, Finding("L3-C", LEVEL_NOTICE, nothing,
            "$(spoken_date(rec.date)) is recorded as closed. No ledger will be generated for it, and " *
            "the next working day will open with $(carried), carried straight through.", nothing))
    end

    # Sort by level so the UI can render in severity order without re-sorting,
    # and so a STOP is never displayed below a HINT.
    sort!(findings, by = f -> f.level)
    return findings
end

# --- Helpers the caller uses to decide what to do ---------------------------

"Any Level 1 finding present? If so the day must not be saved."
has_stops(findings::Vector{Finding}) = any(f -> f.level == LEVEL_STOP, findings)

stops(findings::Vector{Finding}) = filter(f -> f.level == LEVEL_STOP, findings)

"""
    needs_reason(findings)

True when the day carries an unexplained difference and therefore cannot be
committed without a typed explanation.

Warnings Guide §8: the typed reason is the entire value of a Level 2 warning.
A week later, "miscounted the 500 notes" and "no idea" lead to very different
conversations, and nobody reconstructs that from memory. Requiring typing also
makes saving a deliberate act rather than a reflex click.
"""
needs_reason(findings::Vector{Finding}) = any(f -> f.level == LEVEL_EXPLAIN, findings)

"""
    reason_for(rec, f) -> String

The typed reason that explains Level 2 finding `f`. A difference in the opening
balance (L2-B) is explained by `rec.opening_reason`, which the form asks for at
the start of the day; anything else by `rec.reason`, asked for at the end. One
reason cannot stand in for the other: a day can have both differences, and
they happened at different times for different reasons.
"""
reason_for(rec::DayRecord, f::Finding) =
    f.field === :opening_balance ? rec.opening_reason : rec.reason

"""
    unexplained(findings, rec) -> Vector{Finding}

The Level 2 findings whose own reason is blank. The day cannot be saved while
this is not empty.
"""
unexplained(findings::Vector{Finding}, rec::DayRecord) =
    filter(f -> f.level == LEVEL_EXPLAIN && isempty(strip(reason_for(rec, f))), findings)

end # module Checks
