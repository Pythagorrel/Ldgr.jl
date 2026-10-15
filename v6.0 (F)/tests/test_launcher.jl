# =============================================================================
# test_launcher.jl — the app-window launcher: launch flags and reset_zoom!.
#
# Run from a flattened copy of v4.0 (tests/*.jl next to server.jl):
#       julia --startup-file=no test_launcher.jl
#
# Nothing is started: no server, no browser, no network. Fixtures are written
# to a temp folder of this script's own; the owner's real Chrome profile is
# never read.
# =============================================================================

using Dates
mktempdir_root = mktempdir()
ENV["LEDGER_ROOT"]         = joinpath(mktempdir_root, "records")
ENV["LDGR_NO_BROWSER"]     = "1"
ENV["LDGR_NO_DIGEST"]      = "1"
ENV["LDGR_NO_WARMUP"]      = "1"
ENV["LDGR_NOTIFY_CONFIG"]  = joinpath(mktempdir_root, "no-such-notify.toml")
include("server.jl")
using JSON3

const PASS = Ref(0); const FAIL = Ref(0)
function ok(label, cond)
    cond ? (PASS[] += 1; println("  PASS  $label")) : (FAIL[] += 1; println("  FAIL  $label"))
end

fixture(name, text) = (p = joinpath(mktempdir_root, name); write(p, text); p)
parsed(p) = JSON3.read(read(p, String), Dict{String,Any})
leftovers() = filter(f -> occursin("tmp", f), readdir(mktempdir_root))

println("launch flags")
fl = launch_flags("http://127.0.0.1:1", "C:\\prof")
ok("--start-maximized present", "--start-maximized" in fl)
ok("--window-size absent", !any(startswith(f, "--window-size") for f in fl))
ok("--app, profile, no-first-run, no-default-browser-check kept",
   "--app=http://127.0.0.1:1" in fl && "--user-data-dir=C:\\prof" in fl &&
   "--no-first-run" in fl && "--no-default-browser-check" in fl)

println("numeric form and object form")
p = fixture("num.json", """{"a":1,"partition":{"per_host_zoom_levels":{"x":{"127.0.0.1":-1.5,"localhost":{"zoom_level":-2.0,"last_modified":"13400000000000000"}}}}}""")
ok("returns true when it changed something", reset_zoom!(p))
d = parsed(p)
ok("both hosts gone", isempty(d["partition"]["per_host_zoom_levels"]["x"]))
ok("other top-level key kept", d["a"] == 1)

p = fixture("obj.json", """{"partition":{"per_host_zoom_levels":{"x":{"127.0.0.1":{"zoom_level":-1.2239010857415449,"last_modified":"13400000000000000"}}}}}""")
ok("object form: true", reset_zoom!(p))
ok("object form: entry gone", !haskey(parsed(p)["partition"]["per_host_zoom_levels"]["x"], "127.0.0.1"))

println("two partitions, other hosts, default zoom")
p = fixture("multi.json", """{"partition":{"default_zoom_level":{"x":-0.5},"per_host_zoom_levels":{"x":{"127.0.0.1":-1,"example.com":1.25},"y":{"localhost":-3,"127.0.0.1":-1,"other.org":{"zoom_level":2.0}}}}}""")
ok("multi: true", reset_zoom!(p))
d = parsed(p)["partition"]
ok("partition x: local host removed", !haskey(d["per_host_zoom_levels"]["x"], "127.0.0.1"))
ok("partition y: both removed", !haskey(d["per_host_zoom_levels"]["y"], "localhost") && !haskey(d["per_host_zoom_levels"]["y"], "127.0.0.1"))
ok("other hosts kept", d["per_host_zoom_levels"]["x"]["example.com"] == 1.25 &&
   d["per_host_zoom_levels"]["y"]["other.org"]["zoom_level"] == 2.0)
ok("default_zoom_level removed", !haskey(d, "default_zoom_level"))

println("round trip keeps Chrome's values")
p = fixture("rt.json", """{"big":"13400000000000000","nested":{"a":{"b":[1,2,{"c":null}]},"t":true},"uni":"caf\\u00e9 \\u2603 \\ud83d\\ude00","n":123456789012,"f":0.1,"partition":{"default_zoom_level":{"x":1}}}""")
before = parsed(p)
reset_zoom!(p)
after = parsed(p)
delete!(before["partition"], "default_zoom_level")
ok("big-integer string, nesting, unicode, numbers unchanged", before == after)
ok("unicode text intact", after["uni"] == "café ☃ 😀" && after["big"] == "13400000000000000")

println("untouched, missing, invalid")
p = fixture("plain.json", """{"partition":{"per_host_zoom_levels":{"x":{"example.com":1}}}}""")
b0 = read(p); m0 = mtime(p); sleep(1.1)
ok("nothing to remove: false", !reset_zoom!(p))
ok("file bytes identical", read(p) == b0)
ok("mtime unchanged", mtime(p) == m0)
ok("missing file: false", !reset_zoom!(joinpath(mktempdir_root, "absent.json")))
p = fixture("bad.json", """{"partition": {"per_host_zoom_levels": """)
b0 = read(p)
ok("invalid JSON: false", !reset_zoom!(p))
ok("invalid JSON left byte for byte", read(p) == b0)
p = fixture("nopart.json", """{"a":1}""")
ok("no partition key: false", !reset_zoom!(p))
ok("no temp file left behind", isempty(leftovers()))

println()
println("test_launcher: $(PASS[]) passed, $(FAIL[]) failed")
rm(mktempdir_root; recursive = true, force = true)
exit(FAIL[] == 0 ? 0 : 1)
