#!/usr/bin/env julia
# =============================================================================
# server.jl — the local web server.
#
# RUN IT:   julia server.jl          opens the form in a window automatically
#           julia server.jl 9000     to use a different port
#
# FROM THE REPL (for development):
#           ENV["LDGR_NO_BROWSER"] = "1"    # skip the window on every restart
#           include("server.jl")
#           start()
#
#           Including this file does not start the server on its own — the
#           guard at the bottom only fires when the file is run as a script.
#           Note that PORT is read from ARGS when the file is included, so a
#           REPL started as plain `julia` will always use 8000.
#
# WHAT THIS FILE IS: the boundary between the browser and the bookkeeping code.
# It is the ONLY place where those two meet. The browser speaks JSON about days;
# this file turns that JSON into a DayRecord and hands it to the same
# process_day the command line uses. The browser never learns that ledgers,
# journals, accounts or double-entry exist.
#
# WHY A SERVER RATHER THAN A DOWNLOADED FILE: the old form produced a file you
# then had to find, open a terminal for, and run by hand. Three manual steps per
# day. It also meant every run re-loaded DataFrames and CSV from scratch —
# several seconds before any work began. This process loads them once at
# startup and stays warm, so each submission is effectively instant.
#
# IT LISTENS ON 127.0.0.1 ONLY. That is the loopback address: reachable from
# this machine and nothing else. It is not exposed to the network, and it has
# no authentication because it does not need any. Do not change that host to
# 0.0.0.0 without adding authentication first.
# =============================================================================

using HTTP, JSON3, Dates, DataFrames, Logging, Sockets

include("main.jl")                        # Config, Layout, DayInput, Journal, Ledger, AuditLog, process_day

# v4.0: Checks/Chain/Report come in through main.jl above.

const PUBLIC_DIR = joinpath(@__DIR__, "public")
const PORT = isempty(ARGS) ? 8000 : parse(Int, ARGS[1])

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
json(status::Int, data) = HTTP.Response(status,
    ["Content-Type" => "application/json; charset=utf-8",
     "Cache-Control" => "no-store"], JSON3.write(data))

# One container type, so JSON3 compiles one writer for every refusal rather than
# one for a refusal that names a box and another for a refusal that does not.
# See findings_json for the full explanation. The keys are unchanged.
fail(status::Int, msg::AbstractString; field::Union{Nothing,String}=nothing) =
    json(status, Dict{String,Any}("ok" => false, "error" => msg, "field" => field))

const MIMES = Dict(".html" => "text/html; charset=utf-8",
                   ".js"   => "application/javascript; charset=utf-8",
                   ".css"  => "text/css; charset=utf-8",
                   ".ico"  => "image/x-icon",
                   ".png"  => "image/png",
                   # Chrome ignores a manifest served as octet-stream, so the
                   # install option silently never appears without this line.
                   ".webmanifest" => "application/manifest+json")

"""
    serve_static(path)

Serve a file from public/. `basename` strips any directory component from the
requested path before it is used, so a request for `../../etc/passwd` becomes a
request for `passwd` and simply 404s. Even on loopback, a server should not be
willing to read outside its own folder.
"""
function serve_static(reqpath::AbstractString)
    name = basename(reqpath)
    isempty(name) && (name = "index.html")
    file = joinpath(PUBLIC_DIR, name)
    isfile(file) || return HTTP.Response(404, "Not found")
    ext = lowercase(splitext(name)[2])
    return HTTP.Response(200, ["Content-Type" => get(MIMES, ext, "application/octet-stream"),
                               "Cache-Control" => "no-store"], read(file))
end

# ---------------------------------------------------------------------------
# Capturing warnings so the browser can show them
# ---------------------------------------------------------------------------
"""
A logger that copies warnings into a list while still printing them to the
server console.

WHY: the negative-undeposited-funds warning is raised deep inside Ledger.jl with
`@warn`, which writes to the terminal. Nobody is looking at the terminal any
more. Rather than change Ledger.jl to return warnings (which would mean editing
accounting code for a user-interface reason), the warnings are simply collected
as they pass by and attached to the response.
"""
struct CollectLogger <: Logging.AbstractLogger
    sink::Vector{String}
    parent::Logging.AbstractLogger
end
Logging.min_enabled_level(::CollectLogger) = Logging.Debug
Logging.shouldlog(::CollectLogger, args...) = true
Logging.catch_exceptions(::CollectLogger) = false
function Logging.handle_message(l::CollectLogger, level, message, _module, group, id, file, line; kwargs...)
    level >= Logging.Warn && push!(l.sink, replace(string(message), "\n" => " "))
    Logging.handle_message(l.parent, level, message, _module, group, id, file, line; kwargs...)
end

# ---------------------------------------------------------------------------
# Turning a JSON body into a DayRecord — the trust boundary
# ---------------------------------------------------------------------------
"""
    record_from_payload(body) -> DayRecord

Validates and converts. The browser validates too, but that is purely so the
user gets instant feedback; it is not security and it is not correctness. A
browser can be bypassed, a page can be stale, JavaScript can be disabled. Every
rule the front end enforces is enforced again here, and this is the copy that
counts.

Throws ArgumentError with a human-readable message on any bad input.
"""
function record_from_payload(body)
    haskey(body, :date) || throw(ArgumentError("No date was supplied."))

    d = try
        Date(String(body.date))                      # expects YYYY-MM-DD
    catch
        throw(ArgumentError("\"$(body.date)\" is not a valid date."))
    end

    d > Dates.today() && throw(ArgumentError("$(d) is in the future."))
    year(d) < 2000 && throw(ArgumentError("$(d) is too far in the past to be a real entry."))

    # NEW IN v4.0 — closed days.
    # A closed day is built here rather than trusted from the browser: the
    # opening is carried from the previous record and the closing is set equal
    # to it, so the balance passes through and nobody types a figure for a
    # drawer nobody counted (Warnings Guide L3-C).
    status = String(get(body, :status, DayInput.STATUS_TRADING))
    if status == DayInput.STATUS_CLOSED
        prior = Chain.prior_day(d)
        carried = prior === nothing ? 0.0 : prior.closing
        return DayInput.closed_day(d, carried)
    end

    amounts = DayInput.blank_amounts()               # posting keys 0.0, balances NOT_COUNTED
    raw = get(body, :amounts, nothing)
    if raw !== nothing
        valid = Set(String(colname_of(k)) for k in JOURNAL_KEYS)
        for (name, value) in pairs(raw)
            key = String(name)
            key in valid || throw(ArgumentError("Unknown category \"$key\"."))

            # NEW IN v4.0. An empty string on a CASH BOOK field means the drawer
            # was not counted and must stay NOT_COUNTED so that L1-C fires. On
            # every other field an empty string still means zero, exactly as
            # before. This is the one place the blank/zero distinction crosses
            # the wire, and getting it wrong here would silently invent a
            # balance — so the two cases are separated explicitly rather than
            # sharing a default.
            if value === nothing || (value isa AbstractString && isempty(strip(String(value))))
                amounts[Symbol(key)] = Symbol(key) in CASH_BOOK_KEYS ? DayInput.NOT_COUNTED : 0.0
                continue
            end

            v = value isa Number ? Float64(value) :
                something(tryparse(Float64, strip(String(value))), NaN)
            isnan(v) && throw(ArgumentError("\"$(label_of(Symbol(key)))\" is not a number."))
            v < 0 && throw(ArgumentError("\"$(label_of(Symbol(key)))\" cannot be negative."))
            amounts[Symbol(key)] = v
        end
    end

    # Two reasons, one per difference: `openingReason` for an opening that does
    # not match the last close, `reason` for a day that does not balance.
    reason         = String(get(body, :reason, ""))
    opening_reason = String(get(body, :openingReason, ""))
    return DayRecord(d, amounts, DayInput.STATUS_TRADING, reason, opening_reason)
end

"""
    day_context(d) -> (prior, first_day, genesis, ledger_exists, in_books, next_in_books)

The facts about `d` that both the checks and the response need, read from the
books ONCE.

WHY IT IS ONE CALL. Every one of these answers comes from a file: `prior_day`
walks the month journals backwards, `is_genesis_date` walks them again, `isfile`
stats the ledger, and `on_record` reads the month's journal. `/api/check` and
`/api/save` each needed all of them and each asked for them twice — once through
`day_findings` and once to build their own reply — so a single keypress re-read
the same journal several times over.

`first_day` is only asked when there is no previous day: a day with a contiguous
predecessor has a record before it by definition, so the second walk cannot
return anything but `false` and is skipped.

FIRST DAY, TWO ANSWERS, AND THE DIFFERENCE MATTERS. `first_day` is the fact —
nothing is on file before this date. `genesis` is the question the form puts —
tick the box to accept this opening balance as the starting point. Once the day
is in the books the question has been answered and audited, so `genesis` goes
false and the tick box and its notice disappear, while `first_day` stays true and
keeps the checks from claiming the day before it is missing.

`in_books` and `next_in_books` come from one read of the month's journal: whether
this date has a row, and whether the day after it does — an entry under a day
that is already on record is filling a gap (L3-E).
"""
function day_context(d::Date)
    prior     = Chain.prior_day(d)
    first_day = prior === nothing && Chain.is_genesis_date(d)
    recorded, next_recorded = Chain.on_record(d, d + Day(1))
    return (prior = prior, first_day = first_day,
            genesis = first_day && !recorded,
            ledger_exists = isfile(daily_ledger_path(d)),
            in_books = recorded, next_in_books = next_recorded)
end

"""
    day_findings(rec[, ctx]) -> Vector{Finding}

Run the checks for one day against what is already in the books. Pass `ctx` when
the caller has already looked the day up, so the journals are read once.
"""
day_findings(rec::DayRecord, ctx = day_context(rec.date)) =
    check_day(rec;
              prior_closing = ctx.prior === nothing ? nothing : ctx.prior.closing,
              prior_date    = ctx.prior === nothing ? nothing : ctx.prior.date,
              # The FACT, not the question: the checks decide for themselves
              # whether the first-day notice is still worth showing (see
              # day_context, and Checks.check_day's in_books).
              is_genesis    = ctx.first_day,
              ledger_exists = ctx.ledger_exists,
              in_books      = ctx.in_books,
              next_in_books = ctx.next_in_books)

"""
    findings_json(fs) -> Vector{FindingJSON}
    findings_json(rec) -> Vector{FindingJSON}

Render findings for the browser, running the checks first when given a day.

The browser NEVER decides severity for itself. It is told the level, the code,
a short title and the message, and it renders what it is told. That is what
keeps the two copies of a rule from drifting: there is only one copy, here,
and app.js is a display layer for its output (Handover §4 rule 5).

THE ELEMENT TYPE IS DECLARED, AND THAT IS A SPEED FIX, NOT A STYLE ONE. JSON3
compiles a fresh writer for every distinct Julia TYPE it is asked to serialise.
Built by a bare comprehension, this vector's element type depended on the data:
a list whose `field`s were all strings was one type, a list containing a `field`
of `nothing` was another, an empty list a third. So the first save of each KIND
of day — balanced, with a difference, an Off day, a refusal — paid its own
compile, which is what the operator felt as the Save lag. Naming the type once
means there is one writer, compiled on the first request and reused by every
request after it. The JSON the browser receives is identical.
"""
const FindingJSON = NamedTuple{(:code, :level, :levelName, :title, :field, :message),
                               Tuple{String, Int, String, String, Union{Nothing,String}, String}}

findings_json(fs::Vector{Checks.Finding}) =
    FindingJSON[(code=f.code, level=f.level, levelName=level_name(f.level),
                 title=Checks.finding_title(f),
                 field=f.field === nothing ? nothing : String(f.field),
                 message=f.message) for f in fs]
findings_json(rec::DayRecord) = findings_json(day_findings(rec))

# `saved_record(d)` — the day already in the books, read back from its month's
# journal — used to be defined here. It lives in Chain now, where the held-day
# retry was already doing the same job, and reaches this file through
# `using .Chain` in main.jl. One copy means a blank drawer count and an empty
# reason column come back the same way wherever a saved day is asked for.

"""
True when `d` is already in the books, so saving it again replaces it.

Asked of Chain rather than by building the whole day back from its row: the
answer is one journal read either way, and `day_context` needs it for the date
AND the day after it, which Chain answers in a single pass.
"""
in_books(d::Date) = Chain.on_record(d)

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

"""
GET /api/config

The shape of the form, built from Config.jl at request time.

THIS IS WHY THE FRONT END HAS NO HARDCODED CATEGORY LIST. Add a category to
Config.jl, restart the server, and the field appears in the browser by itself.
The old form had its own copy of the category list, which meant adding one
required editing two files that had no way of noticing they disagreed.
"""
function handle_config()
    group(cats) = [(key=String(c.key), label=c.label) for c in cats]
    return json(200, (
        ok = true,
        today = string(Dates.today()),
        groups = [
            (id="cash",     title="Cash & Card Takings",
             hint="(Money taken in over the counter and through the card machines)",
             categories=group(cash_eq_in)),
            (id="expenses", title="Expenses",
             hint="(Money paid out of petty cash during the day)",
             categories=group(expense)),
            (id="other",    title="Banking & Related Party",
             hint="(Deposits here means cash set aside or sent for deposit)",
             categories=group(vcat(deposit, related_party))),
            # NEW IN v4.0. The cash book is sent as its own group so the form
            # can render the balances separately and label them as counted
            # figures. It is generated from Config like every other group, so
            # the front end still holds no category names of its own.
            (id="cashbook", title="Cash Book — counted, not calculated",
             hint="Count the drawer. Do not work these out from the figures above — " *
                  "that is what makes the check meaningful.",
             categories=group(cash_book)),
        ],
        keyOrder = [String(k) for k in KEY_ORDER],
        # Sent so the running total on the entry screen can show the banked figure
        # without the browser having to know that a category called "deposits"
        # exists. The front end holds no category names of its own.
        depositKey = String(deposit[1].key),
        # v4.0: sent so app.js can compute a live PREDICTED closing balance to
        # display beside the counted one, without knowing any category names.
        openingKey  = String(:opening_balance),
        closingKey  = String(:closing_balance),
        inflowKeys  = [String(k) for k in IDENTITY_INFLOW_KEYS],
        outflowKeys = [String(k) for k in IDENTITY_OUTFLOW_KEYS],
        labels = Dict(String(k) => label_of(k) for k in JOURNAL_KEYS),
    ))
end

"""
GET /api/day?date=YYYY-MM-DD

A day that is already in the books, so the form can load it back to correct it
("Edit that day"). `day` is null when that date has not been saved.

These are the figures that were typed for THAT date, balances included, and
they are sent only when someone asks to edit that date. Nothing here fills in
a day that has not been entered, so no balance is pre-filled or worked out for
anyone (README rules 3 and 4).
"""
function handle_day(uri)
    q = HTTP.queryparams(uri)
    haskey(q, "date") || return fail(400, "No date given.")
    d = try Date(q["date"]) catch; return fail(400, "Not a valid date.") end

    rec = saved_record(d)
    # One JSON shape, whether or not the day is on record — see findings_json
    # for why the types are pinned. "A day that has not been saved" is the same
    # response with `day` null, not a differently shaped one.
    rec === nothing && return json(200, Dict{String,Any}("ok" => true, "day" => nothing))

    # NaN cannot be represented in JSON, so an uncounted balance is sent as
    # null and app.js renders it as an empty box.
    amounts = Dict{String,Any}()
    for k in JOURNAL_KEYS
        v = rec.amounts[k]
        amounts[String(colname_of(k))] = isnan(v) ? nothing : v
    end
    day = Dict{String,Any}("date"          => string(rec.date),
                           "amounts"       => amounts,
                           "status"        => rec.status,
                           "reason"        => rec.reason,
                           "openingReason" => rec.opening_reason)
    return json(200, Dict{String,Any}("ok" => true, "day" => day))
end

"""
GET /api/prior?date=YYYY-MM-DD

What the previous calendar day closed at, so the form can show the operator what
their opening balance is expected to match.

DELIBERATELY NOT PRE-FILLED INTO THE FIELD. Showing the figure helps; typing it
into the box would make the overnight check compare a number against itself and
pass every time (Warnings Guide §8). The response is labelled `expected` rather
than `value` for that reason.
"""
function handle_prior(uri)
    q = HTTP.queryparams(uri)
    haskey(q, "date") || return fail(400, "No date given.")
    d = try Date(q["date"]) catch; return fail(400, "Not a valid date.") end

    # One JSON shape whether or not there is a prior day: `priorDate` and
    # `expected` are null rather than of a different type, so this endpoint has
    # a single serialiser (see findings_json). The journals are read once, by
    # day_context, rather than once for the prior day and again for genesis.
    ctx = day_context(d)
    prior = ctx.prior
    return json(200, Dict{String,Any}(
        "ok"        => true,
        # The FACT here, not the question. This line under the opening balance
        # says what the date IS — "this would be the first day on record" — and
        # that stays true after the day has been saved. The tick box is the
        # question, and it is `genesis` from /api/check.
        "genesis"   => ctx.first_day,
        "hasPrior"  => prior !== nothing,
        "priorDate" => prior === nothing ? nothing : string(prior.date),
        "expected"  => prior === nothing ? nothing : prior.closing))
end

"""
POST /api/check — run the checks WITHOUT saving anything.

Lets the form show a Level 2 difference and ask for a reason before the day is
saved, rather than rejecting it afterwards.

It also sends three facts about the date itself, which the form needs before
Save is pressed:
  * `genesis`: nothing is on record before this date AND it has not been saved
    yet, so saving it needs the first-day box ticked. A first day that is
    already in the books has answered that question once and is not asked
    again (see day_context);
  * `hasDailyLedger`: a ledger file already exists for this date, and stays as
    it is unless the replace box is ticked;
  * `inBooks`: this date is already saved, so saving it again replaces it.

THE RESPONSE IS A Dict{String,Any} FOR SPEED, not for taste. `predicted`,
`available` and `paidOut` are a number on a day with figures and `nothing` on a
day without, and a NamedTuple whose field types follow its values is a new type
to JSON3 each time — a fresh writer compiled while the operator waits. One
declared container means one writer. See findings_json for the reasoning. The
keys and values are exactly what app.js read before.
"""
function handle_check(req)
    body = try JSON3.read(String(req.body)) catch; return fail(400, "The request could not be read.") end
    rec = try record_from_payload(body) catch e
        return fail(400, e isa ArgumentError ? e.msg : "That day could not be read.")
    end

    # The books are consulted once for this date and the answers are reused for
    # both the checks and the three facts below.
    ctx = day_context(rec.date)
    fs  = findings_json(day_findings(rec, ctx))

    # Convert NaN to nothing so JSON3 serialises it as null. v4.0 sends the two
    # sides of the prediction as well, so the form can explain a negative one as
    # a deficit instead of showing a negative balance. Same rule: the cash
    # available is NaN while the opening balance is blank.
    safe(x) = (x isa Number && !isfinite(x)) ? nothing : x
    closed = is_closed(rec)

    return json(200, Dict{String,Any}(
        "ok"             => true,
        "findings"       => fs,
        "predicted"      => closed ? nothing : safe(Checks.predicted_closing(rec)),
        "available"      => closed ? nothing : safe(Checks.cash_available(rec)),
        "paidOut"        => closed ? nothing : safe(Checks.identity_outflow(rec)),
        "needsReason"    => any(f -> f.level == Checks.LEVEL_EXPLAIN, fs),
        "blocked"        => any(f -> f.level == Checks.LEVEL_STOP, fs),
        "genesis"        => ctx.genesis,
        "hasDailyLedger" => ctx.ledger_exists,
        "inBooks"        => ctx.in_books))
end

"""
POST /api/save — check one day and write it to the books.

The only endpoint that writes to the books. It does for one day exactly what
the command line does: the checks, then process_day, then the daily report.

NOTHING WAITS IN BETWEEN. Days used to sit on a notepad until a Review screen
sent them all to the books at once. The checks already refuse anything that
cannot be saved, and the form shows them while the figures are typed, so a day
is written the moment it is saved. That also means the next day is checked
against it straight away, rather than only once a whole batch had been written.

The three refusals below come before process_day so that the form gets an
answer it can act on. process_day makes the same tests again, and its copy is
the one that counts (Handover §4 rule 5).
"""
function handle_save(req)
    body = try
        JSON3.read(String(req.body))
    catch
        return fail(400, "The request could not be read.")
    end

    rec = try
        record_from_payload(body)
    catch e
        return fail(400, e isa ArgumentError ? e.msg : "That day could not be accepted.")
    end

    # A STOP: something on this day cannot have happened. The books are read
    # once for this date, by day_context, and the genesis answer below is the
    # same one the checks were given rather than a second walk of the journals.
    ctx = day_context(rec.date)

    # WHAT THE BOOKS SAY BEFORE THIS SAVE TOUCHES THEM. Read here, and nowhere
    # after process_day, because `upsert_day!` replaces the day's row in place:
    # the moment the save runs, the figures it overwrote are gone, and this is
    # the only chance to know what the row held. The change log needs them to be
    # able to say what moved. Asked only when the date is already in the books,
    # so an ordinary first save of a day pays nothing for it.
    previous = ctx.in_books ? Chain.saved_record(rec.date) : nothing

    raw = day_findings(rec, ctx)
    fs = findings_json(raw)
    if any(f -> f.level == Checks.LEVEL_STOP, fs)
        return json(400, (ok=false, error="This day cannot be saved yet.", findings=fs))
    end

    # A difference with no reason. The browser asks for the reason as well, but
    # only so the operator hears about it at once. The form's fix for a save
    # race depends on this refusal (W6): Save pressed right after the last
    # figure can beat the check that brings up the reason box. Each difference
    # needs its own reason (Checks.reason_for). Closed days never raise a
    # Level 2 finding, so they are never refused here.
    silent = Checks.unexplained(raw, rec)
    if !isempty(silent)
        for_opening = any(f -> f.field === :opening_balance, silent)
        for_day     = any(f -> f.field !== :opening_balance, silent)
        msg = for_opening && for_day ?
                  "The opening balance doesn't match the last close and this day doesn't balance. " *
                  "Add a short reason for each before saving it." :
              for_opening ? "The opening balance doesn't match the last close. Add a short reason before saving it." :
                            "This day doesn't balance. Add a short reason before saving it."
        return json(400, (ok=false, error=msg, findings=fs, needsReason=true))
    end

    force        = get(body, :force, false) === true          # QuickBooks re-import confirmed
    allowGenesis = get(body, :allowGenesis, false) === true    # first-ever opening balance accepted

    # The first day on record is accepted ONCE, explicitly: the tick box in the
    # form, or --first-day on the command line. `ctx.genesis` is false once the
    # date is in the books, so correcting the first day later is an ordinary
    # save — it is not asked to authorise itself again, and process_day makes the
    # same distinction rather than taking this refusal's word for it.
    if ctx.genesis && !allowGenesis
        return json(400, (ok=false, needsGenesis=true,
                          error="This is the first day on record. Tick the box to accept its " *
                                "opening balance as the starting point, then save again."))
    end

    warnings = String[]
    logger = CollectLogger(warnings, Logging.current_logger())
    outcome = try
        Logging.with_logger(logger) do
            process_day(rec; force=force, echo=false, allow_genesis=allowGenesis)
        end
    catch e
        @error "Could not save $(rec.date)" exception=(e, catch_backtrace())
        return json(500, (ok=false, error="This day could not be saved: " * sprint(showerror, e)))
    end

    # v4.0: the report is written on EVERY save, not only when something went
    # wrong. Silence is ambiguous — a report saying "entered, balanced" also
    # proves the program ran, which an absent report cannot. A second save on
    # the same day adds to the same file, as a second command-line run does.
    try
        Report.write_report([outcome])
    catch e
        @warn "Report could not be written" exception=e
    end

    # The change log: one row for this day, and one for every held ledger this
    # save released. It is the only place a timestamp and the figures that were
    # replaced are written down, because the journal keeps neither — and it is
    # what the daily report is built from.
    #
    # ITS OWN try, AFTER THE BOOKS ARE WRITTEN, AND IT NEVER CHANGES THE REPLY.
    # The day is already saved and correct by this point. A paper trail that
    # could refuse a save, or that could turn a good save into an error on the
    # screen, would be worse than no paper trail at all.
    try
        Changes.after_save(outcome; rec = rec, previous = previous, before = ctx)
    catch e
        @warn "The change log could not be written" exception=e
    end

    # One declared container, for the same reason as /api/check: `released` is
    # empty on most saves and holds dates on the save that fills a gap, and a
    # NamedTuple whose field types follow its values is a second type for JSON3
    # to compile a writer for. The keys are exactly what app.js read before.
    return json(200, Dict{String,Any}(
        "ok"          => true,
        "date"        => string(outcome.date),
        "closed"      => outcome.closed,
        "journal"     => outcome.journal,
        "dailyLedger" => outcome.daily_ledger,
        "released"    => String[string(d) for d in outcome.released],
        "warnings"    => warnings))
end

"""
    same_day(typed, saved) -> Bool

True when the day on screen is the day in the books: the same kind of day, the
same figures in every box and the same reasons. The two variance columns are
left out because they are worked out by the save, never typed. A blank drawer
count (NOT_COUNTED, stored as NaN) only equals another blank one. For an Off
day the balances are the server's own carried figures, so only the kind of day
is compared.
"""
function same_day(typed::DayRecord, saved::DayRecord)
    typed.status == saved.status || return false
    is_closed(typed) && return true
    for k in JOURNAL_KEYS
        k in VARIANCE_KEYS && continue
        a, b = typed.amounts[k], saved.amounts[k]
        if isnan(a) || isnan(b)
            isnan(a) && isnan(b) || return false
        elseif abs(a - b) >= 0.005
            return false
        end
    end
    return strip(typed.reason) == strip(saved.reason) &&
           strip(typed.opening_reason) == strip(saved.opening_reason)
end

"The date the way the form says it: 14 September 2026."
spoken_date(d::Date) = Dates.format(d, "d U yyyy")

"""
POST /api/next — may the form move on to the day after this one?

Save and Next day used to be one button. They are two now: Save writes the day
(`/api/save`), and Next day asks this endpoint first. It writes nothing. It takes
the same body as `/api/save` and answers with one shape:

    { ok, saved, changed, date, next, error }

  * `saved`   — the date has a row in its month's journal;
  * `changed` — it has, but a figure or a reason on screen is not what that row
                holds, so moving on would leave something unsaved;
  * `next`    — the day after, or null when that day has not happened yet;
  * `error`   — the plain sentence the form shows when it may not move on.

The answer is 200 only when the day is in the books exactly as shown. Otherwise
it is 409, and the form stays on the day. The comparison is made here, against
the journal, because the browser cannot know what the books hold: a page opened
after a save has nothing of its own to compare with.
"""
function handle_next(req)
    body = try JSON3.read(String(req.body)) catch; return fail(400, "The request could not be read.") end
    rec = try record_from_payload(body) catch e
        return fail(400, e isa ArgumentError ? e.msg : "That day could not be read.")
    end

    d = rec.date
    after = d + Day(1)
    answer(status, saved, changed, error) = json(status, Dict{String,Any}(
        "ok"      => status == 200,
        "saved"   => saved,
        "changed" => changed,
        "date"    => string(d),
        "next"    => after > Dates.today() ? nothing : string(after),
        "error"   => error))

    saved = saved_record(d)
    saved === nothing &&
        return answer(409, false, false, "$(spoken_date(d)) has not been saved yet. Save it before moving on.")
    same_day(rec, saved) ||
        return answer(409, true, true, "The figures on screen for $(spoken_date(d)) have not been saved. Save them before moving on.")
    return answer(200, true, false, nothing)
end

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
# Routing is written out by hand rather than using HTTP.Router so that this file
# does not depend on which version of HTTP.jl happens to be installed.
function router(req::HTTP.Request)
    uri = HTTP.URI(req.target)
    path = uri.path
    m = req.method

    try
        if m == "GET" && (path == "/" || path == "/index.html")
            return serve_static("index.html")
        elseif m == "GET" && path == "/api/config"
            return handle_config()
        elseif m == "GET" && path == "/api/day"
            return handle_day(uri)
        elseif m == "GET" && path == "/api/prior"
            return handle_prior(uri)
        elseif m == "POST" && path == "/api/check"
            return handle_check(req)
        elseif m == "POST" && path == "/api/save"
            return handle_save(req)
        elseif m == "POST" && path == "/api/next"
            return handle_next(req)
        elseif m == "GET"
            return serve_static(path)
        else
            return HTTP.Response(405, "Method not allowed")
        end
    catch e
        # An unhandled error must not take the server down mid-session; report it
        # and keep listening.
        @error "Unhandled error" exception=(e, catch_backtrace())
        return fail(500, "Something went wrong on the server. Check the terminal window.")
    end
end

# ---------------------------------------------------------------------------
# Warm-up
#
# WHY THIS EXISTS. Julia compiles a method the first time it is called, and the
# save path is the longest in the program: the checks, the journal reader, the
# CSV writer, the ledger builder, the audit log, the report and JSON3's writer
# for the response. Until the Review screen was removed that cost was paid once
# per batch, on a button nobody minded waiting for. Now it lands on the first
# Save of the session — measured at about five seconds, on a form that gives no
# sign anything is happening.
#
# It runs once, at start(), while the operator is still reaching for the mouse.
# Set LDGR_NO_WARMUP=1 to skip it during development, where the server is
# restarted after every edit and the first save is usually a throwaway.
#
# IT WRITES NOTHING TO THE BOOKS. That is the whole design constraint, and it is
# why this is a warm-up rather than a rehearsal save. Every endpoint it calls is
# read-only; every file it touches is Layout.warmup_file(), a scratch file in the
# OS temp folder deleted in a `finally` on the way out. The Records folder is
# byte-for-byte as it was. tests/test_endpoints.jl asserts that by listing the
# folder before and after.
# ---------------------------------------------------------------------------

"""
    warmup()

Compile the check-and-save path without writing to the books.

Everything here is a real call through the real code — the endpoints go through
`router` exactly as a browser's would — because compiling the function a request
actually reaches is the only thing that helps. The synthetic days are chosen to
cover the shapes that used to compile separately: a day that balances, a day
with both differences, a day whose closing balance is still blank, a day that
cannot be saved, an Off day, an unknown category and a body that cannot be read
at all.

The writing half cannot be CALLED without touching the books, so it is compiled
by signature with `precompile` instead.

Runs synchronously. Julia is single-threaded here and compilation does not
yield, so a background warm-up would simply stall the page's own first requests
instead of the startup banner.
"""
function warmup()
    post(path, body) = router(HTTP.Request("POST", path,
                              ["Content-Type" => "application/json"], JSON3.write(body)))
    post_raw(path, s) = router(HTTP.Request("POST", path,
                              ["Content-Type" => "application/json"], s))
    get_(path) = router(HTTP.Request("GET", path))

    # --- The writing half, compiled by signature ----------------------------
    # It cannot be CALLED without touching the books, so `precompile` infers it
    # instead. FIRST, not last: inferring the whole save tree in one pass also
    # covers most of what the calls below would otherwise compile piecemeal, and
    # measurably so — the same warm-up costs about 23 s with this block at the
    # end and about 16 s with it here.
    precompile(process_day, (DayRecord,))
    precompile(Core.kwcall, (NamedTuple{(:force, :echo, :allow_genesis),
                                        Tuple{Bool,Bool,Bool}},
                             typeof(process_day), DayRecord))
    precompile(_write_daily_ledger!, (AuditSession, DayRecord, Float64, Float64, Bool, Bool, Bool))
    precompile(_retry_pending!, (AuditSession, Int, Int, Bool, Bool))
    precompile(handle_save, (HTTP.Request,))
    precompile(write_journal, (String, DataFrame))
    precompile(write_ledger_csv, (Dict{Symbol,Float64}, Dict{Symbol,Float64},
                                  Dict{Symbol,Float64}, Dict{Symbol,Float64}, String))

    today = Dates.today()
    # 1000 + 100 − 400 − 100 − 100 = 500, so the default day balances exactly.
    figures(; o=1000.0, s=100.0, e=400.0, dep=100.0, b=100.0, c=500.0) = Dict(
        "opening_balance" => o, "cash_sales" => s,
        "POS_Scotia" => 0, "POS_RBL" => 0, "POS_U" => 0,
        "doctor_fees" => e, "medical_supply_costs" => 0,
        "miscellaneous_costs" => 0, "taxi_fare" => 0,
        "deposits" => dep, "Mr_Boyle" => b, "closing_balance" => c)

    # --- The read-only endpoints, through the router ------------------------
    get_("/")
    get_("/api/config")
    get_("/api/prior?date=$today")
    get_("/api/day?date=$today")

    base = figures()
    # A day that balances, with both reasons typed.
    post("/api/check", (date=string(today), amounts=base, reason="r", openingReason="o"))
    # Both differences at once: the closing does not match the prediction and the
    # opening does not match the last close.
    post("/api/check", (date=string(today), amounts=merge(base, Dict("closing_balance" => 600)),
                        reason="r", openingReason="o"))
    # The closing balance still blank — the L1-C Stop, and the overnight check
    # running anyway so the opening box can be asked about straight away.
    post("/api/check", (date=string(today), amounts=merge(base, Dict("closing_balance" => nothing))))
    # A Stop: more money paid out than the drawer ever held.
    post("/api/check", (date=string(today), amounts=merge(base, Dict("deposits" => 5000))))
    # An Off day.
    post("/api/check", (date=string(today), status="closed"))
    # Two bodies that cannot be turned into a day.
    post("/api/check", (date=string(today), amounts=Dict("bogus" => 1)))
    post_raw("/api/check", "{not json")

    # A day built so that EVERY diagnostic tip fires at once, because each one is
    # a separate branch and whichever is missed here is the one the operator
    # waits for. The difference is $900: divisible by 9, equal to the taxi fare,
    # nine times the supplies figure, and equal to the card takings.
    post("/api/check", (date=string(today), reason="r", openingReason="o", amounts=Dict(
        "opening_balance" => 1000.0, "cash_sales" => 5000.0,
        "POS_Scotia" => 900.0, "POS_RBL" => 0, "POS_U" => 0,
        "doctor_fees" => 400.0, "medical_supply_costs" => 100.0,
        "miscellaneous_costs" => 0, "taxi_fare" => 900.0,
        "deposits" => 100.0, "Mr_Boyle" => 100.0, "closing_balance" => 3500.0)))

    # /api/next on a date that has almost certainly not been saved. It reads the
    # journal and writes nothing, whichever answer it gives.
    post("/api/next", (date=string(today), amounts=base, reason="r", openingReason="o"))

    # --- The checks, against each shape of prior day ------------------------
    rec = record_from_payload(JSON3.read(JSON3.write(
              (date=string(today), amounts=base, reason="r", openingReason="o"))))
    # The last two columns are "this date is already saved" and "the day after it
    # is", so the first-day notice being skipped and the gap-filling reminder are
    # both compiled here rather than on the save that fills a real gap.
    for (prior_closing, genesis, ledger, saved, next_saved) in
            ((nothing, true,  false, false, false),
             (nothing, true,  true,  true,  false),
             (900.0,   false, true,  false, true),
             (500.0,   false, false, true,  true))
        fs = check_day(rec; prior_closing=prior_closing, prior_date=today - Day(1),
                       is_genesis=genesis, ledger_exists=ledger,
                       in_books=saved, next_in_books=next_saved)
        js = findings_json(fs)
        # The 400 bodies that carry findings.
        JSON3.write((ok=false, error="e", findings=js))
        JSON3.write((ok=false, error="e", findings=js, needsReason=true))
        Checks.unexplained(fs, rec)
        Checks.balance_checks(rec, prior_closing)
    end
    JSON3.write((ok=false, needsGenesis=true, error="e"))
    JSON3.write(Dict{String,Any}("ok" => false, "error" => "e", "field" => nothing))

    # --- The journal, the ledger and the audit log, on a scratch file -------
    closed = DayInput.closed_day(today - Day(1), 500.0)
    df = empty_journal()
    df, _ = upsert_day!(df, rec)
    df, _ = upsert_day!(df, rec)          # the replace branch
    df, _ = upsert_day!(df, closed)

    scratch = Layout.warmup_file()
    try
        CSV.write(scratch, df)
        df2 = read_journal(scratch)
        journal_totals(df2); variance_totals(df2); day_count(df2)
        Chain._latest_before(df2, today); Chain._pending_from(df2)

        # Rebuilding a DayRecord from a journal row — the exact call every
        # saved day, every held-day retry and every change-log row goes
        # through, rather than a copy of it written out here.
        Chain._record_from(df2, today)

        # One change-log row written and read back on the same scratch file, so
        # the CSV writer in append mode and the reader `rows_between` uses are
        # both compiled before the first save has to pay for them. Inside this
        # `try` so the `finally` below removes the file whatever happens.
        Changes.warmup_roundtrip(scratch)

        cash, expenses, deposits, rp = DayInput.group_amounts(rec)
        rows = build_ledger_rows(cash, expenses, deposits, rp;
                                 day_variance=-5.0, overnight_variance=5.0)
        CSV.write(scratch, DataFrame(rows))
        CSV.write(scratch, DataFrame(Account=String[], Debit=Union{Missing,Float64}[],
                                                       Credit=Union{Missing,Float64}[]))

        session = AuditSession(scratch)
        log_event(session, "warm-up"; echo=false)
        log_entry(session; header="warm-up")
    finally
        rm(scratch; force=true)
    end

    # --- The chain and the report -------------------------------------------
    Chain.prior_day(today); Chain.is_genesis_date(today); Chain.ledger_ready(rec)
    Chain.on_record(today); Chain.on_record(today, today + Day(1))
    Chain.pending_ledgers(year(today), month(today))
    Chain.month_chain_check(year(today), month(today))
    saved_record(today); in_books(today); day_context(today)
    same_day(rec, rec); spoken_date(today)

    # The report is BUILT but not written — write_report opens a file under ROOT,
    # and the warm-up may not. Building it is the expensive half.
    outcome = (date = today, ok = true, closed = false, journal = "added",
               daily_ledger = "written", monthly_ledger = "created", days_in_month = 1,
               day_variance = -5.0, overnight_variance = 5.0, reason = "r",
               opening_reason = "o", released = Date[], released_days = ReleasedDay[],
               findings = Checks.Finding[], output_dir = "", events = String[])
    Report.build_report([outcome])
    Report.report_path(today)

    # --- The change log and the daily report ---------------------------------
    # Built, never written. `Changes.after_save` appends under ROOT, which the
    # warm-up may not touch, so it is compiled by signature only; everything
    # else below is read-only and answers honestly on an empty records folder —
    # no rows, nothing waiting, no mailbox, no report yet. `build_digest` is the
    # expensive half of half past six and is the one worth doing here.
    precompile(Core.kwcall, (NamedTuple{(:rec, :previous, :before),
                                        Tuple{DayRecord, Nothing, typeof(day_context(today))}},
                             typeof(Changes.after_save), typeof(outcome)))
    Changes.first_seen(today)
    Changes.rows_between(nothing, Dates.now())
    Chain.waiting_ledgers()
    Notify.settings(); Notify.enabled()
    Notify.latest_cutoff(Dates.now(), Dates.Time(18, 30))
    Notify.last_reported()
    Notify.build_digest(nothing, Dates.now())

    # Every response shape JSON3 has to write, including the 200 from a save.
    JSON3.write(Dict{String,Any}("ok" => true, "date" => string(today), "closed" => false,
                                 "journal" => "added", "dailyLedger" => "written",
                                 "released" => String[], "warnings" => String[]))

    # One warning through the collecting logger, sent to devnull rather than the
    # terminal: the point is to compile the path, not to print a fake warning in
    # front of the operator on every start.
    Logging.with_logger(CollectLogger(String[], Logging.ConsoleLogger(devnull))) do
        @warn "warm-up"
    end
    sprint(showerror, ErrorException("warm-up"))

    # The one signature that needs a sample outcome to name its argument type.
    precompile(Report.write_report, (Vector{typeof(outcome)},))

    # --- One real round trip over a socket ----------------------------------
    # Everything above goes through `router` in-process, which leaves HTTP.jl's
    # own server side — accepting a connection, parsing the request, streaming
    # the reply — to compile on the browser's first request: measured at eleven
    # seconds with the packages already in a system image, on a form that shows
    # nothing while it waits. So the warm-up listens once on a spare loopback
    # port the OS picks, answers three requests to itself, and closes. Nothing
    # else can connect in that time and no fixed port is taken.
    Logging.with_logger(Logging.NullLogger()) do
        port, tcp = Sockets.listenany(Sockets.ip"127.0.0.1", 49152)
        # The OS has picked a free port. Hand the socket back and let HTTP.jl
        # bind the port itself: `serve!(f, host, port)` is the one signature
        # shared by HTTP.jl 1.x and 2.x, whereas the `server=` keyword that took
        # an open TCPServer was dropped in 2.x and made this step fail on a
        # machine with the newer package. The moment between close and bind is
        # on loopback and shorter than anything else could use.
        close(tcp)
        srv = HTTP.serve!(router, "127.0.0.1", Int(port))
        try
            url = "http://127.0.0.1:$port"
            HTTP.get("$url/api/config")
            HTTP.get("$url/")
            HTTP.post("$url/api/check", ["Content-Type" => "application/json"],
                      JSON3.write((date=string(today), amounts=base)))
            HTTP.post("$url/api/next", ["Content-Type" => "application/json"],
                      JSON3.write((date=string(today), amounts=base)); status_exception=false)
        finally
            close(srv)
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Launching the UI
#
# The form is a web page, but the person using it should not have to know that.
# On Windows we look for Chrome or Edge and open the page with --app=, which
# gives a window with no address bar, no tabs and no bookmarks — it looks like
# a desktop application. If neither is found we fall back to whatever the
# default browser is. Nothing here is required for the server to work; a
# failure to open a window leaves a running server and a printed URL.
#
# --user-data-dir points the window at its own private Chrome profile. Without
# it the window joins the user's existing browser session, which means their
# extensions load into it and closing their last ordinary window can take this
# one with it. The first launch will therefore look like a brand new browser:
# no bookmarks, no sign-in, no extensions. That is correct, not a fault.
# ---------------------------------------------------------------------------

"""
    browser_candidates() -> Vector{String}

Places Chrome and Edge are normally installed on Windows, most-preferred first.
Built fresh on each call rather than stored in a `const`: the per-user install
path depends on LOCALAPPDATA, and a `const` would freeze whatever that was when
the file was first loaded. That does not matter much today, but it matters a
great deal once this is compiled with PackageCompiler, where module-level code
runs on the build machine.
"""
function browser_candidates()
    lad = get(ENV, "LOCALAPPDATA", "")
    paths = [
        raw"C:\Program Files\Google\Chrome\Application\chrome.exe",
        raw"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        raw"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        raw"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    # Per-user Chrome installs are the most common kind, so try that first.
    isempty(lad) || pushfirst!(paths,
        joinpath(lad, raw"Google\Chrome\Application\chrome.exe"))
    return paths
end

"""
    listening(port) -> Bool

True if something is already accepting connections on that port of loopback.
Used for two things: to notice that a second copy of the app has been started,
and to wait until the server is actually up before pointing a browser at it.
"""
listening(port::Int) =
    try
        close(Sockets.connect("127.0.0.1", port))
        true
    catch
        false
    end

"""
    profile_dir() -> String

A private browser profile for ldgr, in the right per-platform location for
user data. Deliberately not inside the install directory: once this ships as a
compiled app it may live under Program Files, where a standard user cannot
write.
"""
function profile_dir()
    base = if Sys.iswindows()
        get(ENV, "LOCALAPPDATA", tempdir())
    elseif Sys.isapple()
        joinpath(homedir(), "Library", "Application Support")
    else
        get(ENV, "XDG_DATA_HOME", joinpath(homedir(), ".local", "share"))
    end
    return joinpath(base, "ldgr", "browser")
end

"""
    open_browser(port)

Open the form. Never throws in normal use, and never blocks: `wait = false`
matters because a Chrome window opened with its own profile stays alive until
the user closes it, and a blocking `run` here would mean the server never
starts.

--no-first-run and --no-default-browser-check exist because the profile is
private and therefore new on first launch, which otherwise triggers Chrome's
welcome wizard and a "make Chrome your default" prompt in front of the form.
"""
function open_browser(port::Int)
    url = "http://127.0.0.1:$port"

    if Sys.iswindows()
        cands = browser_candidates()
        i = findfirst(isfile, cands)
        if i !== nothing
            profile = profile_dir()
            mkpath(profile)
            run(`$(cands[i]) --app=$url --user-data-dir=$profile
                 --no-first-run --no-default-browser-check
                 --window-size=1280,900`; wait = false)
            return nothing
        end
        run(`cmd /c start "" $url`; wait = false)     # default browser
    elseif Sys.isapple()
        run(`open $url`; wait = false)
    else
        run(`xdg-open $url`; wait = false)
    end
    return nothing
end

# ---------------------------------------------------------------------------
function start()
    # A second launch should show the window belonging to the first, not die
    # with an "address already in use" error. People double-click twice.
    if listening(PORT)
        println()
        println("  Already running on port $PORT — opening the window.")
        println()
        flush(stdout)
        open_browser(PORT)
        return
    end

    mkpath(Layout.ROOT)
    println()
    println("  Bookkeeping entry form")
    println("  ----------------------")
    println("  Records folder : $(Layout.ROOT)")
    # Said out loud at every start, because the failure this guards against is
    # silence: an owner who believes a report is coming and never learns that
    # the settings file was never filled in.
    println("  Email          : " * (Notify.enabled() ?
        "on -> $(Notify.recipient())  (daily report at $(Notify.send_at_text()))" :
        "off (no notify.toml)"))
    println()
    println("  Open this in your browser:  http://127.0.0.1:$PORT")
    println("  Press Ctrl+C in this window to stop.")
    println()
    flush(stdout)          # so the address above appears immediately, not when buffered

    # Compile the check-and-save path before anybody can press Save. Set
    # LDGR_NO_WARMUP=1 to skip it. A warm-up that fails has cost nothing and must
    # never stop the server starting — the first save simply pays for its own
    # compilation, as it did before this existed.
    if get(ENV, "LDGR_NO_WARMUP", "") != "1"
        println("  Warming up...")
        flush(stdout)
        try
            t0 = time()
            warmup()
            println("  Ready (warm-up took $(round(time() - t0, digits=1)) s)")
        catch e
            @warn "Warm-up did not finish. The first save will be slower than usual." exception = e
        end
        println()
        flush(stdout)
    end

    # The daily report. Nothing here runs unless notify.toml names a mailbox.
    #
    # `preload` pulls the email package in now rather than at half past six, so
    # the one thing that can be slow about sending happens while the operator is
    # already waiting for the server to come up. Failing to load it is not fatal:
    # the report is written to the outbox either way, and a message in the outbox
    # goes out on a later attempt.
    if Notify.enabled()
        try
            Notify.preload()
        catch e
            @warn "The email package could not be loaded. The daily report will stay in the outbox until it is." exception = e
        end
    end
    # Safe to call whatever the settings say: it returns without doing anything
    # when LDGR_NO_DIGEST=1 or there is no mailbox configured, and it creates no
    # folders in that case.
    Notify.start_schedule!()

    # Set LDGR_NO_BROWSER=1 to suppress this during development.
    if get(ENV, "LDGR_NO_BROWSER", "") == ""
        @async begin
            # Wait for the listener to bind before pointing anything at it,
            # otherwise the browser races the server and gets a refused
            # connection. Five seconds is far longer than this ever takes.
            for _ in 1:100
                listening(PORT) && break
                sleep(0.05)
            end
            try
                open_browser(PORT)
            catch e
                @warn "Could not open a browser window automatically. " *
                      "Open http://127.0.0.1:$PORT by hand." exception = e
            end
        end
    end

    HTTP.serve(router, "127.0.0.1", PORT)
end

if abspath(PROGRAM_FILE) == @__FILE__
    start()
end
