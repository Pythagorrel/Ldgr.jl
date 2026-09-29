module Report

using Dates, DataFrames
using ..Config
using ..Layout
using ..DayInput
using ..Journal
using ..Checks
using ..Chain

# =============================================================================
# REPORT — the end-of-run summary, written to a local text file.
#
# ENTIRELY NEW IN v4.0.
#
# NO EMAIL YET, DELIBERATELY. This writes a file and nothing else. When email is
# added it should send THIS text and not assemble its own, so that what lands in
# an inbox and what sits on disk cannot drift apart.
#
# WHAT BELONGS IN A REPORT AND WHAT DOES NOT. The report is a notification. It
# is not a record, and nothing should depend on it: it cannot be totalled, aged,
# audited against, or trusted to have been read. Every figure it mentions exists
# independently — variances are journal columns and ledger rows, held days are
# derived from the disk, confirmations are in the audit log. If this module were
# deleted the books would be unaffected. That is the correct relationship.
#
# THE STANDING ITEMS MATTER MORE THAN THE NEW ONES. Pending ledgers are listed
# EVERY day until they clear, not once when they arise. A held day is silent by
# nature — nothing errors, QuickBooks imports cleanly, and the problem only
# surfaces at month end. Repeating the list daily is the whole defence.
# =============================================================================

export write_report, report_path, build_report

"Where a day's report lands. One file per calendar day the program was run.
The path itself is built in Layout, like every other path in the program
(README rule 2); this is the name the rest of the program already calls, so
delegating keeps both spellings meaning the same file."
report_path(d::Date=Dates.today()) = Layout.report_path(d)

# ONE MONEY FORMAT FOR THE WHOLE PROGRAM. This used to print its own figures, so
# a shortage the form called $5,000.00 arrived in the report as "$5000.0" — the
# same amount in two dialects, in two documents somebody reads side by side.
# Checks.money is the formatter the warnings use: grouped digits, always two
# decimals, integer cents throughout. The sign is put outside the currency symbol
# here, as the rest of this file already did, because a report figure can be
# negative where a warning's never is (it names a SURPLUS or a SHORTAGE instead).
_money(x) = isnan(x) ? "(not counted)" :
            (x < 0 ? "-" : "") * Checks.money(abs(x))

_rule(c="-") = repeat(c, 74)

"""
    build_report(outcomes; run_date) -> String

Assemble the report text from what a commit produced.

`outcomes` is the vector of NamedTuples returned by process_day, one per day.
Everything else is re-read from disk rather than passed in, so the report
describes the state of the books as they now are rather than what the run
believed it was doing.
"""
function build_report(outcomes::Vector; run_date::Date=Dates.today())
    io = IOBuffer()
    user = get(ENV, "USERNAME", get(ENV, "USER", "unknown"))

    println(io, _rule("="))
    println(io, "  LDGR DAILY REPORT — $(run_date)")
    println(io, "  Generated $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS")) by $(user)")
    println(io, "  Records folder: $(Layout.ROOT)")
    println(io, _rule("="))
    println(io)

    # --- 1. What was entered ------------------------------------------------
    println(io, "DAYS ENTERED IN THIS RUN")
    println(io, _rule())
    if isempty(outcomes)
        println(io, "  (none)")
    else
        for o in outcomes
            status = o.ok ? (o.closed ? "closed day" : "recorded") : "FAILED"
            println(io, "  $(o.date)   $(status)   journal: $(o.journal)   ledger: $(o.daily_ledger)")
        end
    end
    println(io)

    # --- 2. Differences -----------------------------------------------------
    # Listed with the typed reason attached. The reason is the entire value of a
    # Level 2 warning: a week later "miscounted the 500 notes" and "no idea"
    # lead to very different conversations, and nobody reconstructs that from
    # memory.
    println(io, "DIFFERENCES REQUIRING ATTENTION")
    println(io, _rule())
    any_var = false
    for o in outcomes
        o.ok || continue
        # Each difference with its own reason: the day's for a difference during
        # trading, the opening balance's for one overnight.
        for (amt, what, why) in ((o.day_variance, "during trading", o.reason),
                                 (o.overnight_variance, "overnight", o.opening_reason))
            if abs(amt) >= 0.005
                any_var = true
                kind = amt > 0 ? "SURPLUS" : "SHORTAGE"
                println(io, "  $(o.date)   $(kind) of $(_money(abs(amt))) $(what)")
                println(io, "               reason: $(isempty(why) ? "(none given)" : why)")
            end
        end
    end
    any_var || println(io, "  None. Every day entered in this run balanced.")
    println(io)

    # --- 3. Held ledgers — the standing item --------------------------------
    println(io, "LEDGERS WAITING ON A MISSING DAY")
    println(io, _rule())
    months = unique([(year(o.date), month(o.date)) for o in outcomes if o.ok])
    isempty(months) && (months = [(year(run_date), month(run_date))])
    held_any = false
    for (y, m) in sort(months)
        for d in Chain.pending_ledgers(y, m)
            held_any = true
            prior = Chain.prior_record(d)
            waiting = prior === nothing ? "the day before it" : "$(d - Day(1))"
            println(io, "  $(d)   entered, but no ledger yet — waiting on $(waiting)")
        end
    end
    if held_any
        println(io)
        println(io, "  These days are SAVED. Only their ledgers are outstanding, and each")
        println(io, "  will be produced automatically once the day before it is entered.")
        println(io, "  This list repeats every day until it is empty.")
    else
        println(io, "  None. Every recorded day has a ledger.")
    end
    println(io)

    # --- 4. QuickBooks re-import confirmations ------------------------------
    println(io, "LEDGERS REGENERATED FOR A DAY THAT ALREADY HAD ONE")
    println(io, _rule())
    redone = [o for o in outcomes if o.ok && o.daily_ledger == "overwritten"]
    if isempty(redone)
        println(io, "  None.")
    else
        for o in redone
            println(io, "  $(o.date)   confirmed by the operator as safe to re-import")
        end
        println(io)
        println(io, "  ldgr cannot see inside QuickBooks. If any of these were already")
        println(io, "  imported and not deleted first, that day is now counted twice.")
    end
    println(io)

    # --- 5. Month position --------------------------------------------------
    println(io, "MONTH TO DATE")
    println(io, _rule())
    for (y, m) in sort(months)
        p = journal_path(y, m)
        isfile(p) || continue
        df = read_journal(p)
        v = variance_totals(df)
        chk = Chain.month_chain_check(y, m)

        println(io, "  $(Layout.month_tag(y, m))")
        println(io, "     days recorded          : $(nrow(df))  (trading: $(day_count(df)))")
        println(io, "     cash over/short, day   : $(_money(v.day))")
        println(io, "     cash over/short, night : $(_money(v.overnight))")
        println(io, "     cash over/short, TOTAL : $(_money(v.total))")
        if chk.note != ""
            println(io, "     month check            : not applicable — $(chk.note)")
        elseif chk.ok
            println(io, "     month check            : OK — recorded movement matches the balances")
        else
            println(io, "     month check            : ** OFF BY $(_money(chk.diff)) **")
            println(io, "        The month's recorded movement does not match the span from the")
            println(io, "        first opening balance to the last closing balance. That usually")
            println(io, "        means a day is missing, or a day was edited without the day")
            println(io, "        after it being re-checked.")
        end
    end
    println(io)

    println(io, _rule("="))
    println(io, "  A day that balances has passed one test. It can still be wrong:")
    println(io, "  two errors that cancel, a deposit and a transfer swapped, or a POS")
    println(io, "  figure in the wrong bank all pass every check in this program.")
    println(io, "  Only the bank statements can find those.")
    println(io, _rule("="))

    return String(take!(io))
end

"""
    write_report(outcomes; run_date) -> path

Build the report and write it. Appends if the program is run more than once in a
day, so an afternoon session cannot erase the morning's record.
"""
function write_report(outcomes::Vector; run_date::Date=Dates.today())
    p = report_path(run_date)
    mkpath(dirname(p))
    open(p, "a") do io
        println(io, build_report(outcomes; run_date=run_date))
    end
    return p
end

end # module Report
