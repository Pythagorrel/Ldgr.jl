# =============================================================================
# test_app_mode.jl — the v6.0 packaged-app code paths.
#
# Run from a flattened copy (tests/*.jl next to server.jl):
#       julia --startup-file=no test_app_mode.jl
#
# What it covers: start_app (refusals, the LDGR-READY line, a chosen port, the
# stop on stdin closing, a save in flight at that moment), Notify.finish!,
# PUBLIC_FILES, Layout.__init__ and the 500 sentence.
#
# SAFETY. Child servers are real processes listening on 127.0.0.1, each with its
# own scratch LEDGER_ROOT, LDGR_NO_DIGEST=1, LDGR_NO_BROWSER=1 and a notify
# config that does not exist. Nothing contacts Resend or the internet: the
# in-process mailer is a fake and Resend.API_BASE[] points at a closed port.
# =============================================================================

using Dates, Sockets
scratch = mktempdir()
ENV["LEDGER_ROOT"]         = joinpath(scratch, "records-main")
ENV["LDGR_NO_BROWSER"]     = "1"
ENV["LDGR_NO_DIGEST"]      = "1"
ENV["LDGR_NO_WARMUP"]      = "1"
ENV["LDGR_NOTIFY_CONFIG"]  = joinpath(scratch, "no-such-notify.toml")
basename(ENV["LEDGER_ROOT"]) == "Records" && error("LEDGER_ROOT points at the real books")
include("server.jl")
using JSON3, HTTP

const PASS = Ref(0); const FAIL = Ref(0)
function ok(label, cond)
    cond ? (PASS[] += 1; println("  PASS  $label")) : (FAIL[] += 1; println("  FAIL  $label"))
end
const SRC = @__DIR__

# A port nothing listens on: bind port 0, read the number, close it again.
function free_port()
    s = Sockets.listen(ip"127.0.0.1", 0)
    p = Int(getsockname(s)[2]); close(s); p
end
Resend.API_BASE[] = "http://127.0.0.1:$(free_port())"   # closed, in case anything ever tried

# ---------------------------------------------------------------- child process
mutable struct Child
    proc::Base.Process
    lines::Vector{String}
    reader::Task
    errfile::String
end
function spawn_child(env::Dict; code = "include(\"server.jl\"); exit(start_app())")
    e = Dict{String,String}(ENV)
    for (k, v) in env
        v === nothing ? delete!(e, k) : (e[k] = v)
    end
    cmd = setenv(Cmd(`$(Base.julia_cmd()) --startup-file=no -e $code`; dir = SRC), e)
    errf = joinpath(scratch, "stderr-$(rand(UInt32)).txt")
    proc = open(pipeline(cmd; stderr = errf), "r+")
    lines = String[]
    rd = @async try
        for l in eachline(proc)
            push!(lines, l)
        end
    catch
    end
    Child(proc, lines, rd, errf)
end
function child_env(root; extra...)
    d = Dict{String,Union{Nothing,String}}(
        "LEDGER_ROOT" => root, "LDGR_NO_DIGEST" => "1", "LDGR_NO_BROWSER" => "1",
        "LDGR_NOTIFY_CONFIG" => joinpath(scratch, "no-such-notify.toml"))
    for (k, v) in extra; d[String(k)] = v; end
    d
end
waitfor(pred, secs) = timedwait(pred, float(secs); pollint = 0.05) == :ok
const READY = r"^LDGR-READY http://127\.0\.0\.1:(\d+)$"
function ready_port(c::Child, secs)
    waitfor(() -> any(l -> occursin(READY, l), c.lines) || process_exited(c.proc), secs) || return 0
    i = findfirst(l -> occursin(READY, l), c.lines)
    i === nothing ? 0 : parse(Int, match(READY, c.lines[i])[1])
end
"Close the child's stdin and wait for it to end. Returns (exited, exitcode, seconds)."
function stop_child(c::Child; secs = 15)
    t0 = time()
    try close(c.proc.in) catch end
    done = waitfor(() -> process_exited(c.proc), secs)
    done || (try kill(c.proc) catch end)
    waitfor(() -> istaskdone(c.reader), 5)
    (done, done ? c.proc.exitcode : -1, time() - t0)
end
find_file(root, name) = begin
    for (d, _, fs) in walkdir(root)
        name in fs && return joinpath(d, name)
    end
    nothing
end
http(m, url; body = nothing) = HTTP.request(m, url,
    body === nothing ? [] : ["Content-Type" => "application/json"], body === nothing ? "" : body;
    status_exception = false, retry = false, readtimeout = 180, connect_timeout = 10)
amounts(o, c) = Dict("opening_balance" => o, "cash_sales" => 98400.0, "POS_Scotia" => 0, "POS_RBL" => 0,
    "POS_U" => 0, "doctor_fees" => 22400.0, "medical_supply_costs" => 0, "miscellaneous_costs" => 0,
    "taxi_fare" => 0, "deposits" => 75000.0, "Mr_Boyle" => 0.0, "closing_balance" => c)
save_body(d) = JSON3.write((date = string(d), amounts = amounts(1270.0, 2270.0), allowGenesis = true))

# =============================================================================
println("1. start_app refuses without LEDGER_ROOT or LDGR_NOTIFY_CONFIG")
before = sort(readdir(SRC))
c = spawn_child(child_env(nothing))
(done, code, _) = stop_child(c; secs = 180)   # it is still loading server.jl (~30 s without the image)
ok("no LEDGER_ROOT: the child ended", done)
ok("no LEDGER_ROOT: exit code 2", code == 2)
ok("no LEDGER_ROOT: stdout is exactly the one FAIL line", c.lines == ["LDGR-FAIL LEDGER_ROOT is not set."])
ok("no LEDGER_ROOT: no Records folder was created beside the source", !isdir(joinpath(SRC, "Records")))
ok("no LEDGER_ROOT: the source folder is unchanged", sort(readdir(SRC)) == before)

root1 = joinpath(scratch, "records-nonotify")
c = spawn_child(child_env(root1; LDGR_NOTIFY_CONFIG = nothing))
(done, code, _) = stop_child(c; secs = 180)
ok("no LDGR_NOTIFY_CONFIG: the child ended", done)
ok("no LDGR_NOTIFY_CONFIG: exit code 2", code == 2)
ok("no LDGR_NOTIFY_CONFIG: stdout is exactly the one FAIL line", c.lines == ["LDGR-FAIL LDGR_NOTIFY_CONFIG is not set."])
ok("no LDGR_NOTIFY_CONFIG: the books folder was not created", !ispath(root1))

c = spawn_child(child_env(""))
(done, code, _) = stop_child(c; secs = 180)
ok("an empty LEDGER_ROOT counts as not set", done && code == 2 && c.lines == ["LDGR-FAIL LEDGER_ROOT is not set."])

# =============================================================================
println("\n2. The normal path (no warm-up)")
root2 = joinpath(scratch, "records-normal")
c = spawn_child(child_env(root2; LDGR_NO_WARMUP = "1"))
port = ready_port(c, 120)
ok("READY line printed", port != 0)
ok("the port is not zero and is a real port", 1024 <= port <= 65535)
ok("no READY line before the Records/Email banner lines", something(findfirst(l -> occursin(READY, l), c.lines), 0) >= 3)
ok("Records folder line names the scratch root", any(l -> occursin("Records folder", l) && occursin(root2, l), c.lines))
ok("the books folder was created", isdir(root2))
base = "http://127.0.0.1:$port"
r = http("GET", base * "/")
ok("GET / is 200 HTML", r.status == 200 && occursin("text/html", HTTP.header(r, "Content-Type")) && occursin("<html", lowercase(String(r.body))))
r = http("GET", base * "/app.js")
ok("GET /app.js is 200 JavaScript", r.status == 200 && occursin("javascript", HTTP.header(r, "Content-Type")) && length(r.body) > 1000)
r = http("GET", base * "/nosuch.js")
ok("GET /nosuch.js is 404", r.status == 404)
r = http("POST", base * "/api/check"; body = save_body(Date(2026, 3, 2)))
ok("POST /api/check answers 200 with findings", r.status == 200 && JSON3.read(String(r.body)).ok == true)
r = http("POST", base * "/api/save"; body = save_body(Date(2026, 3, 2)))
sb = JSON3.read(String(r.body))
ok("POST /api/save answers 200 ok", r.status == 200 && sb.ok == true)
jf = find_file(root2, "Daily Journal 03-2026.csv")
ok("the Daily Journal exists under the scratch root", jf !== nothing && startswith(jf, root2) && filesize(jf) > 0)
ok("the change log was written too", find_file(root2, "Change Log.csv") !== nothing)
ok("the child is still running while stdin is open", !process_exited(c.proc))
(done, code, secs) = stop_child(c)
ok("closing stdin ends the child within 15 s", done && secs < 15)
ok("exit code 0", code == 0)
ok("it printed '  Stopped.'", "  Stopped." in c.lines)
ok("'  Closing...' came before '  Stopped.'",
   (i = findfirst(==("  Closing..."), c.lines); j = findfirst(==("  Stopped."), c.lines); i !== nothing && j !== nothing && i < j))
ok("nothing was written outside the scratch root", !isdir(joinpath(SRC, "Records")))
r = try http("GET", base * "/") catch e; nothing end
ok("the port no longer answers", r === nothing)

# =============================================================================
println("\n2b. The normal path with the warm-up")
root2b = joinpath(scratch, "records-warm")
c = spawn_child(child_env(root2b; LDGR_NO_WARMUP = nothing))
port = ready_port(c, 240)
ok("READY line printed after the warm-up", port != 0)
ok("the warm-up line was printed before READY",
   (i = findfirst(l -> occursin("Warm-up took", l), c.lines); j = findfirst(l -> occursin(READY, l), c.lines); i !== nothing && j !== nothing && i < j))
ok("GET / answers 200", port != 0 && http("GET", "http://127.0.0.1:$port/").status == 200)
ok("the warm-up wrote no journal under the books", find_file(root2b, "Daily Journal 03-2026.csv") === nothing)
(done, code, secs) = stop_child(c)
ok("stops cleanly: exit 0, Stopped.", done && code == 0 && "  Stopped." in c.lines && secs < 15)
ok("no warm-up warning on stderr", !occursin("Warm-up did not finish", read(c.errfile, String)))

# =============================================================================
println("\n3. start_app(port = N) listens on exactly that port")
want = free_port()
root3 = joinpath(scratch, "records-port")
c = spawn_child(child_env(root3; LDGR_NO_WARMUP = "1");
                code = "include(\"server.jl\"); exit(start_app(port = $want))")
got = ready_port(c, 120)
ok("READY names the port asked for", got == want)
ok("exact line", "LDGR-READY http://127.0.0.1:$want" in c.lines)
ok("it serves on that port", got != 0 && http("GET", "http://127.0.0.1:$want/").status == 200)
(done, code, _) = stop_child(c)
ok("and stops with 0", done && code == 0)

# =============================================================================
println("\n4. A save in flight when stdin closes still gets its answer")
root4 = joinpath(scratch, "records-inflight")
c = spawn_child(child_env(root4; LDGR_NO_WARMUP = "1"))
port = ready_port(c, 120)
ok("READY", port != 0)
# No warm-up, so the first save compiles the whole save path: it takes seconds,
# which is what makes "in flight" certain without a race on the request.
answer = Ref{Any}(nothing)
t = @async try
    answer[] = http("POST", "http://127.0.0.1:$port/api/save"; body = save_body(Date(2026, 4, 6)))
catch e
    answer[] = e
end
sleep(0.3)
inflight = !istaskdone(t) && answer[] === nothing
try close(c.proc.in) catch end
ok("the save was still unanswered when stdin closed", inflight)
waitfor(() -> istaskdone(t), 120)
ok("the save answered 200 ok", answer[] isa HTTP.Response && answer[].status == 200 &&
   JSON3.read(String(answer[].body)).ok == true)
done = waitfor(() -> process_exited(c.proc), 30)
waitfor(() -> istaskdone(c.reader), 5)
ok("the child then ended with 0", done && c.proc.exitcode == 0)
ok("it printed Stopped.", "  Stopped." in c.lines)
jf = find_file(root4, "Daily Journal 04-2026.csv")
ok("the day is in the books", jf !== nothing && occursin("2026-04-06", read(jf, String)))

# =============================================================================
println("\n5. Notify.finish!")
function fresh_notify!()
    Notify.stop_schedule!()
    Notify.MAILER[] = nothing
    Notify.BACKOFF[] = nothing
    return nothing
end
CALLS = Any[]
fake_ok = (send = (k, e, i) -> (push!(CALLS, :send); "id-1"), cancel = (k, i) -> (push!(CALLS, :cancel); nothing))
fresh_notify!()
ok("scheduler not running: :off", Notify.finish!() === :off)

fresh_notify!()
Notify.SCHEDULE[] = Timer(3600); Notify.MAILER[] = fake_ok
empty!(CALLS)
r = try Notify.finish!() catch e; e end
ok("running with email off: :ok, no throw", r === :ok)
ok("SCHEDULE[] is cleared", Notify.SCHEDULE[] === nothing)
ok("email off: the mailer was never called", isempty(CALLS))
ok("calling it again says :off", Notify.finish!() === :off)

# with email configured (fake key, fake mailer) and a mailer that throws
cfgfile = joinpath(scratch, "fake-notify.toml")
write(cfgfile, """
to = "owner@example.invalid"
api_key = "re_FAKE_apptests_key_0123456789abcdefXYZ"
from = "LDGR Daily Report <reports@example.invalid>"
send_at = "17:30"
""")
withenv("LDGR_NOTIFY_CONFIG" => cfgfile) do
    fresh_notify!()
    Notify.SCHEDULE[] = Timer(3600)
    Notify.MAILER[] = (send = (k, e, i) -> (push!(CALLS, :send); error("boom: the mailer broke")),
                       cancel = (k, i) -> (push!(CALLS, :cancel); nothing))
    empty!(CALLS)
    r = try Notify.finish!() catch e; e end
    ok("a mailer that throws: finish! does not throw", r === :ok)
    ok("the tick really ran and reached the mailer", :send in CALLS)
    ok("SCHEDULE[] is cleared", Notify.SCHEDULE[] === nothing)

    # a recording mailer that works
    fresh_notify!()
    rm(joinpath(scratch, "records-main", "Notifications"); recursive = true, force = true)
    Notify.SCHEDULE[] = Timer(3600)
    Notify.MAILER[] = fake_ok
    empty!(CALLS)
    r = try Notify.finish!() catch e; e end
    ok("a working fake mailer: :ok", r === :ok)
    ok("the last report was handed to the fake mailer", :send in CALLS)

    # settings that throw: an unreadable path (a folder where the file should be)
    fresh_notify!()
    Notify.SCHEDULE[] = Timer(3600)
    Notify.MAILER[] = fake_ok
    withenv("LDGR_NOTIFY_CONFIG" => scratch) do   # a folder, not a file
        r = try Notify.finish!() catch e; e end
        ok("settings that cannot be used: finish! does not throw", r === :ok || r === :error)
    end
end
fresh_notify!()

# BUSY held by another task
fresh_notify!()
Notify.SCHEDULE[] = Timer(3600)
gate = Channel{Nothing}(1); held = Ref(false)
holder = @async lock(Notify.BUSY) do
    held[] = true
    take!(gate)
end
waitfor(() -> held[], 5)
t0 = time()
r = Notify.finish!(timeout = 1)
dt = time() - t0
ok("BUSY held elsewhere: :timed_out", r === :timed_out)
ok("and it took about 1 s (not 10, not instant)", 0.9 <= dt <= 3.0)
ok("SCHEDULE[] is cleared even then", Notify.SCHEDULE[] === nothing)
put!(gate, nothing); wait(holder)
ok("the lock is free again afterwards", (sleep(0.3); !islocked(Notify.BUSY)))
fresh_notify!()

# =============================================================================
println("\n6. PUBLIC_FILES")
ok("the Dict is empty when loaded from source", isempty(PUBLIC_FILES))
ok("empty: app.js is read from disk (200)", serve_static("/app.js").status == 200)
ok("empty: nosuch.js is 404", serve_static("/nosuch.js").status == 404)
ok("empty: / serves index.html", serve_static("/").status == 200)
try
    PUBLIC_FILES["zz-test.js"] = Vector{UInt8}(codeunits("var answer = 42;"))
    r = serve_static("/zz-test.js")
    ok("filled: the file is served from memory", r.status == 200 && String(r.body) == "var answer = 42;")
    ok("filled: right content type", HTTP.header(r, "Content-Type") == MIMES[".js"])
    ok("filled: Cache-Control no-store kept", HTTP.header(r, "Cache-Control") == "no-store")
    ok("filled: app.js (on disk) is now 404", serve_static("/app.js").status == 404)
    ok("filled: index.html (on disk) is now 404", serve_static("/").status == 404)
    ok("filled: a path trick still resolves by file name only", serve_static("/../../zz-test.js").status == 200)
    ok("filled: an unknown name is 404", serve_static("/nosuch.js").status == 404)
    ok("through the router too", router(HTTP.Request("GET", "/zz-test.js")).status == 200 &&
       router(HTTP.Request("GET", "/app.js")).status == 404)
    PUBLIC_FILES["zz-test.js"][1] = UInt8('X')
    r1 = serve_static("/zz-test.js"); r1.body[1] = UInt8('Q')
    ok("changing a response body does not change the stored file", PUBLIC_FILES["zz-test.js"][1] == UInt8('X'))
finally
    empty!(PUBLIC_FILES)
end
ok("restored: empty again and disk serving works", isempty(PUBLIC_FILES) && serve_static("/app.js").status == 200)

# =============================================================================
println("\n7. Layout.__init__ reads LEDGER_ROOT when it runs")
orig_root = Layout.ROOT
other = joinpath(scratch, "records-other")
try
    ENV["LEDGER_ROOT"] = other
    Layout.__init__()
    ok("ROOT follows the environment", Layout.ROOT == other)
    ok("journal_path is under it", startswith(Layout.journal_path(2026, 5), other))
    ok("the change log and notifications paths are under it too",
       startswith(Layout.change_log_path(), other) && startswith(Layout.notifications_dir(), other))
    ok("nothing was created by changing ROOT", !ispath(other))
finally
    ENV["LEDGER_ROOT"] = joinpath(scratch, "records-main")
    Layout.__init__()
end
ok("restored", Layout.ROOT == joinpath(scratch, "records-main") && orig_root == Layout.ROOT)
delete!(ENV, "LEDGER_ROOT"); Layout.__init__()
ok("with LEDGER_ROOT unset it falls back to <source>/Records", Layout.ROOT == joinpath(SRC, "Records"))
ENV["LEDGER_ROOT"] = joinpath(scratch, "records-main"); Layout.__init__()
ok("and is restored again", Layout.ROOT == joinpath(scratch, "records-main"))

# =============================================================================
println("\n8. The 500 sentence")
SENTENCE = "Something went wrong. Try again. If it keeps happening, contact the technician."
function err_of(resp)
    try String(JSON3.read(String(resp.body)).error) catch; "" end
end
# Known real one: an outflow of 1e308 makes Checks.money(Inf) throw while the
# L1-B message is built (a JSON-only input; the form caps the boxes).
big = JSON3.write((date = "2026-05-05", amounts = Dict("opening_balance" => 1000.0,
        "cash_sales" => 1000.0, "closing_balance" => 1000.0, "doctor_fees" => 1e308)))
candidates = [
    ("POST", "/api/check", big),
    ("POST", "/api/save", "[]"),
    ("POST", "/api/save", "null"),
    ("POST", "/api/save", "42"),
    ("POST", "/api/save", "{\"date\":\"2026-05-05\",\"amounts\":[]}"),
    ("POST", "/api/save", "{\"date\":\"2026-05-05\",\"amounts\":5}"),
    ("POST", "/api/next", "[]"),
    ("POST", "/api/next", "{\"date\":\"2026-05-05\",\"amounts\":5}"),
    ("POST", "/api/check", "[]"),
    ("POST", "/api/check", "{\"date\":\"2026-05-05\",\"amounts\":5}"),
    ("GET",  "/api/day?date=2026-13-45", ""),
]
hit = nothing
logger = Base.CoreLogging.NullLogger()
for (m, p, b) in candidates
    resp = Base.CoreLogging.with_logger(logger) do
        router(HTTP.Request(m, p, ["Content-Type" => "application/json"], b))
    end
    if resp.status == 500
        global hit = (m, p, b, resp); break
    end
end
if hit !== nothing
    println("      (reached by a real request: $(hit[1]) $(hit[2]) $(hit[3]))")
    ok("a real request reaches the catch and answers 500", hit[4].status == 500)
    ok("the error text is the owner-approved sentence", err_of(hit[4]) == SENTENCE)
    ok("the 500 body is JSON with an error field", !isempty(err_of(hit[4])))
else
    println("      (no real request reached the catch; the sentence is checked in the router source)")
    src = read(joinpath(SRC, "server.jl"), String)
    i = findfirst("function router", src)
    seg = i === nothing ? "" : src[first(i):min(end, first(i) + 2500)]
    ok("the literal sentence is in the router's catch", occursin("fail(500, \"$SENTENCE\")", seg))
end
resp = Base.CoreLogging.with_logger(logger) do
    router(HTTP.Request("GET", "/api/day?date=2026-05-05", [], ""))
end
ok("an ordinary unsaved day still answers 200 (the catch is not over-eager)", resp.status == 200)
ok("the server stayed up after those requests", router(HTTP.Request("GET", "/api/config")).status == 200)

println()
println("PASSED $(PASS[]) FAILED $(FAIL[])")
rm(scratch; recursive = true, force = true)
exit(FAIL[] == 0 ? 0 : 1)
