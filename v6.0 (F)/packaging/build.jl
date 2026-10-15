# =============================================================================
# build.jl: builds the packaged LDGR app (v6.0) into  ..\dist\LDGR\  and the zips.
#
# RUN (from anywhere; paths are worked out from this file):
#     julia --startup-file=no packaging\build.jl all        everything (~20 min)
#     julia --startup-file=no packaging\build.jl stage      package + environment only
#     julia --startup-file=no packaging\build.jl image      runtime image (needs stage)
#     julia --startup-file=no packaging\build.jl assemble   dist folder + zips (needs image)
#
# Needs: Julia 1.10.12 with PackageCompiler in the default environment, the
# in-box C# compiler, and esbuild (LDGR_ESBUILD, or <build dir>\node\...).
# Intermediate files go in LDGR_BUILD_DIR (default %TEMP%\ldgrb): a short path
# with no spaces, because the image build's linker and the package caches do
# not like long ones. Nothing is written to ~\.julia: the build's depot comes
# first in JULIA_DEPOT_PATH.
#
# SAFETY: every child process gets LDGR_NO_DIGEST=1, a notify.toml path that
# does not exist and a scratch LEDGER_ROOT, so nothing can be emailed and the
# real books are never opened. notify.toml is never copied into the bundle.
# =============================================================================

using Dates, TOML

const HERE     = @__DIR__                                  # ...\packaging
const PROG     = normpath(joinpath(HERE, ".."))            # ...\vFinal (6.0)
const DIST     = joinpath(PROG, "dist")
const APPDIR   = joinpath(DIST, "LDGR")
const B        = get(ENV, "LDGR_BUILD_DIR", joinpath(tempdir(), "ldgrb"))
const APP_VERSION = strip(read(joinpath(HERE, "VERSION"), String))
const JULIA_HOME = normpath(joinpath(Sys.BINDIR, ".."))
const JULIA_EXE  = joinpath(Sys.BINDIR, "julia.exe")
const CSC = raw"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

# The program's files, by name. A whitelist: tests, handoff notes, prototype.html,
# sample_day.csv and notify.toml can never reach the bundle by accident.
const PROGRAM_JL = ["AuditLog.jl", "Chain.jl", "Changes.jl", "Checks.jl", "Config.jl",
                    "DayInput.jl", "EmailHtml.jl", "getdate.jl", "Journal.jl", "Layout.jl",
                    "Ledger.jl", "main.jl", "Notify.jl", "Report.jl", "Resend.jl", "server.jl"]
const FORM_FILES = ["index.html", "app.js", "styles.css"]

const LDGR_UUID = "e3b1c6d2-6f0a-4c51-9b7e-1d2a4c5b6f70"   # fixed for the life of the app
const DEPS = ["CSV"        => "336ed68f-0bac-5ca0-87d4-7b16caf5d00b",
              "DataFrames" => "a93c6f00-e57d-5684-b7b6-d8193f3e46c0",
              "Dates"      => "ade2ca70-3891-5945-98fb-dc099432e06a",
              "HTTP"       => "cd3eb016-35fb-5094-929b-558a96fad6f3",
              "JSON3"      => "0f8b85d8-7281-11e9-16c2-39a750bddbf1",
              "Logging"    => "56ddb016-857b-54e1-b83d-db4d58db5568",
              "SHA"        => "ea8e919c-243c-51af-8825-aaa63cd721ce",
              "Sockets"    => "6462fe0b-24de-5631-8697-dd941f90decc",
              "TOML"       => "fa267f1f-6049-4f14-aa54-33bafae1ed76"]
const IMAGE_PACKAGES = [:LDGR, :HTTP, :JSON3, :DataFrames, :CSV]

say(xs...) = (println("  ", xs...); flush(stdout))

# Every child process runs with this environment: the build's own depot first,
# email fenced off, scratch books, no inherited Julia settings.
function child_env()
    env = Dict{String,String}()
    for (k, v) in ENV
        startswith(uppercase(k), "JULIA_") && continue
        uppercase(k) in ("LEDGER_ROOT", "LDGR_NOTIFY_CONFIG", "LDGR_DIGEST_NOW") && continue
        env[k] = v
    end
    env["JULIA_DEPOT_PATH"] = join([joinpath(B, "depot"), joinpath(homedir(), ".julia"),
                                    joinpath(JULIA_HOME, "share", "julia")], ';')
    env["LDGR_NO_DIGEST"] = "1"
    env["LDGR_NO_BROWSER"] = "1"
    env["LDGR_NOTIFY_CONFIG"] = joinpath(B, "no-such-notify.toml")
    env["LEDGER_ROOT"] = joinpath(B, "scratch-books")
    env["LDGR_PRECOMPILE_ROOT"] = joinpath(B, "pc")
    return env
end

function julia_child(code::AbstractString; project = joinpath(B, "env"))
    cmd = `$JULIA_EXE --startup-file=no --history-file=no --project=$project -e $code`
    run(setenv(cmd, child_env()))
end

function esbuild()
    p = get(ENV, "LDGR_ESBUILD", joinpath(B, "node", "node_modules", "@esbuild", "win32-x64", "esbuild.exe"))
    isfile(p) || error("esbuild not found at $p. Install it: cd $(joinpath(B, "node")); npm i esbuild@0.28.2")
    return p
end

# --- stage: the package LDGR and the environment that builds it ---------------
function stage()
    VERSION == v"1.10.12" || error("Build with Julia 1.10.12 (this is $VERSION): the runtime is copied from the Julia running this script.")
    pkg = joinpath(B, "pkg", "LDGR")
    rm(pkg; recursive = true, force = true)
    src = joinpath(pkg, "src")
    mkpath(joinpath(src, "public"))
    say("Staging the package in ", pkg)

    for f in PROGRAM_JL
        cp(joinpath(PROG, f), joinpath(src, f))
    end
    cp(joinpath(HERE, "LDGR", "src", "LDGR.jl"), joinpath(src, "LDGR.jl"))
    write(joinpath(src, "version.jl"),
          "const APP_VERSION = \"$APP_VERSION\"\nconst BUILT = \"$(Dates.format(now(), "yyyy-mm-dd"))\"\n")

    # The form: minified (app.js, styles.css) or stripped of comments (index.html).
    pub = joinpath(PROG, "public")
    es = esbuild()
    for f in ("app.js", "styles.css")
        run(`$es $(joinpath(pub, f)) --minify --legal-comments=none --log-level=warning --outfile=$(joinpath(src, "public", f))`)
    end
    html = read(joinpath(pub, "index.html"), String)
    html = replace(html, r"<!--.*?-->"s => "")
    lines = [rstrip(l) for l in split(replace(html, "\r\n" => "\n"), '\n')]
    write(joinpath(src, "public", "index.html"), join(filter(!isempty, lines), "\n") * "\n")
    ico = joinpath(HERE, "icon", "favicon.ico")
    isfile(ico) && cp(ico, joinpath(src, "public", "favicon.ico"))
    # The header image (from packaging\brand\header\), served as image/svg+xml.
    cp(joinpath(pub, "header.svg"), joinpath(src, "public", "header.svg"))
    for f in readdir(joinpath(src, "public"))
        say("  form file ", rpad(f, 12), lpad(filesize(joinpath(src, "public", f)), 8), " bytes",
            isfile(joinpath(pub, f)) ? "  (source $(filesize(joinpath(pub, f))))" : "")
    end

    open(joinpath(pkg, "Project.toml"), "w") do io
        TOML.print(io, Dict("name" => "LDGR", "uuid" => LDGR_UUID, "version" => APP_VERSION,
                            "deps" => Dict(DEPS),
                            "compat" => Dict("HTTP" => "1", "julia" => "1.10")))
    end

    env = joinpath(B, "env")
    rm(env; recursive = true, force = true)
    mkpath(env)
    cp(joinpath(PROG, "Project.toml"), joinpath(env, "Project.toml"))
    cp(joinpath(PROG, "Manifest.toml"), joinpath(env, "Manifest.toml"))
    before = TOML.parsefile(joinpath(env, "Manifest.toml"))
    say("Adding LDGR to the build environment (offline) and precompiling it")
    julia_child("""
        using Pkg
        Pkg.offline(true)
        Pkg.develop(path = raw"$pkg"; preserve = Pkg.PRESERVE_ALL)
        Pkg.precompile(strict = true)
        """)
    after = TOML.parsefile(joinpath(env, "Manifest.toml"))
    pinned(m) = Dict(k => v[1]["version"] for (k, v) in m["deps"] if haskey(v[1], "version") && k != "LDGR")
    pinned(before) == pinned(after) || error("Adding LDGR changed a package version: $(pinned(before)) vs $(pinned(after))")
    say("Package versions unchanged: HTTP ", pinned(after)["HTTP"], ", CSV ", pinned(after)["CSV"],
        ", DataFrames ", pinned(after)["DataFrames"], ", JSON3 ", pinned(after)["JSON3"])
end

# --- image: runtime\ldgr.dll -------------------------------------------------------
function image()
    out = joinpath(B, "ldgr.dll")
    isfile(joinpath(B, "env", "Manifest.toml")) || error("Run the stage step first.")
    rm(out; force = true)
    say("Building the image (about 15-25 minutes). Started ", Dates.format(now(), "HH:MM:SS"))
    t0 = time()
    julia_child("""
        import PackageCompiler
        PackageCompiler.create_sysimage($(repr(IMAGE_PACKAGES));
            project = raw"$(joinpath(B, "env"))",
            sysimage_path = raw"$out",
            precompile_execution_file = raw"$(joinpath(HERE, "precompile_app.jl"))",
            cpu_target = PackageCompiler.default_app_cpu_target())
        """)
    say("Image built in ", round(Int, (time() - t0) / 60), " min: ", out, " (", round(filesize(out) / 2^20, digits = 1), " MB)")
end

# --- assemble: dist\LDGR and the zips -----------------------------------------------
function assemble()
    img = joinpath(B, "ldgr.dll")
    isfile(img) || error("Run the image step first.")
    if isdir(joinpath(APPDIR, "Records")) && !isempty(readdir(joinpath(APPDIR, "Records")))
        error("$(joinpath(APPDIR, "Records")) holds books. Move them out before rebuilding the bundle.")
    end
    rm(APPDIR; recursive = true, force = true)
    rt = joinpath(APPDIR, "runtime")
    mkpath(rt)
    say("Assembling ", APPDIR)

    # Julia itself, without what -J makes unnecessary and what nothing at run time reads.
    cp(JULIA_HOME, joinpath(rt, "julia"))
    rm(joinpath(rt, "julia", "lib", "julia", "sys.dll"))
    rm(joinpath(rt, "julia", "include"); recursive = true, force = true)
    rm(joinpath(rt, "julia", "share", "doc"); recursive = true, force = true)

    cp(img, joinpath(rt, "ldgr.dll"))

    # The OpenSSL artifact, found by asking the build environment where it lives.
    art = readchomp(setenv(`$JULIA_EXE --startup-file=no --project=$(joinpath(B, "env")) -e "import HTTP; print(Base.loaded_modules[Base.PkgId(Base.UUID(\"458c3c95-2e84-50aa-8efc-19380b2a3a95\"), \"OpenSSL_jll\")].artifact_dir)"`, child_env()))
    isdir(art) || error("OpenSSL artifact not found: $art")
    mkpath(joinpath(rt, "depot", "artifacts"))
    cp(art, joinpath(rt, "depot", "artifacts", basename(art)))
    say("OpenSSL artifact ", basename(art))

    mkpath(joinpath(rt, "env"))
    open(joinpath(rt, "env", "Project.toml"), "w") do io
        TOML.print(io, Dict("deps" => Dict("LDGR" => LDGR_UUID, "CSV" => DEPS[1][2], "DataFrames" => DEPS[2][2],
                                           "HTTP" => DEPS[4][2], "JSON3" => DEPS[5][2])))
    end

    cp(joinpath(HERE, "webview2"), joinpath(rt, "webview2"))
    write(joinpath(rt, "VERSION.txt"), "$APP_VERSION (built $(Dates.format(now(), "yyyy-mm-dd")))\r\n")

    # Licences of everything SolRegia did not write.
    notices = joinpath(HERE, "notices.jl")
    if isfile(notices)
        run(setenv(`$JULIA_EXE --startup-file=no $notices $(joinpath(B, "env", "Manifest.toml")) $(joinpath(rt, "THIRD-PARTY-NOTICES.txt")) $art $(joinpath(rt, "julia")) $(joinpath(rt, "webview2"))`, child_env()))
    else
        @warn "packaging\\notices.jl is missing: no THIRD-PARTY-NOTICES.txt"
    end

    mkpath(joinpath(APPDIR, "settings"))
    cp(joinpath(HERE, "settings-README.txt"), joinpath(APPDIR, "settings", "README.txt"))
    cp(joinpath(HERE, "tools"), joinpath(APPDIR, "tools"))

    # The window.
    launcher()
    cp(joinpath(B, "launcher", "LDGR.exe"), joinpath(APPDIR, "LDGR.exe"))

    zips()
end

function launcher()
    outdir = joinpath(B, "launcher")
    rm(outdir; recursive = true, force = true)
    mkpath(outdir)
    wv = joinpath(HERE, "webview2")
    src = joinpath(HERE, "launcher")
    ico = joinpath(HERE, "icon", "ldgr.ico")
    isfile(ico) || error("packaging\\icon\\ldgr.ico is missing (build the icon tool first).")
    exe = joinpath(outdir, "LDGR.exe")
    # The start and closing screens (packaging\brand\), embedded in LDGR.exe so no loose image ships.
    # LDGR.cs reads them by these names; the file for the screen's scaling is picked at run time.
    res = String[]
    for (dir, base) in (("startup", "startup-banner"), ("closing", "closing")), k in ("1x", "1.25x", "1.5x", "2x")
        png = joinpath(HERE, "brand", dir, "$base@$k.png")
        isfile(png) || error("$png is missing.")
        push!(res, "/resource:$png,$base@$k.png")
    end
    run(`$CSC /nologo /target:winexe /platform:x64 /optimize+ /out:$exe /win32icon:$ico
          /win32manifest:$(joinpath(src, "app.manifest"))
          /r:$(joinpath(wv, "Microsoft.Web.WebView2.Core.dll")) /r:$(joinpath(wv, "Microsoft.Web.WebView2.WinForms.dll"))
          /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll
          $res $(joinpath(src, "LDGR.cs"))`)
    say("LDGR.exe ", filesize(exe), " bytes")
end

function zips()
    tar = raw"C:\Windows\System32\tar.exe"
    full = joinpath(DIST, "LDGR-$APP_VERSION.zip")
    upd  = joinpath(DIST, "LDGR-update-$APP_VERSION.zip")
    rm(full; force = true); rm(upd; force = true)
    say("Zipping (a few minutes)")
    run(`$tar -a -c -f $full -C $DIST LDGR`)
    run(`$tar -a -c -f $upd -C $(joinpath(APPDIR, "runtime")) ldgr.dll VERSION.txt`)
    for z in (full, upd)
        say(basename(z), "  ", round(filesize(z) / 2^20, digits = 1), " MB")
    end
end

# -------------------------------------------------------------------------------------
step = isempty(ARGS) ? "all" : ARGS[1]
println("\n  LDGR $APP_VERSION build: $step   (build folder $B)\n")
step in ("all", "stage")    && stage()
step in ("all", "image")    && image()
step in ("all", "assemble") && assemble()
step == "launcher"           && launcher()
step == "zips"               && zips()
println("\n  Done: $step\n")
