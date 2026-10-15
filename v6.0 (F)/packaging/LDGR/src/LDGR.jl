# =============================================================================
# LDGR.jl: the packaged app's wrapper (v6.0). NOT USED IN DEVELOPMENT.
#
# packaging/build.jl copies the program's .jl files beside this one, puts the
# minified form in public/ beside them, writes version.jl, and compiles the
# result into runtime/ldgr.dll as the package `LDGR`. The program itself is
# unchanged: `include("server.jl")` loads exactly what `include("server.jl")`
# loads in the REPL, only inside this module instead of Main.
#
# Three things happen here and nowhere else:
#   1. The form's files are read now, at build time, into PUBLIC_FILES, so the
#      installed app serves them from the image and ships no public/ folder.
#   2. LDGR's own docstrings are removed from the image. They are prose about
#      how the program works, and the owner asked that as little of the source
#      as possible be readable on the clinic's PC.
#   3. app_main(), what LDGR.exe runs: version line, start_app(), exit code.
# =============================================================================
module LDGR

include("version.jl")      # const APP_VERSION, const BUILT (written by build.jl)
include("server.jl")       # the whole program

let dir = joinpath(@__DIR__, "public")
    for name in readdir(dir)
        PUBLIC_FILES[name] = read(joinpath(dir, name))
    end
end

let mods = Module[LDGR]
    for n in names(LDGR; all = true)
        isdefined(LDGR, n) || continue
        v = getfield(LDGR, n)
        v isa Module && v !== LDGR && parentmodule(v) === LDGR && push!(mods, v)
    end
    for m in mods
        empty!(Base.Docs.meta(m))
    end
end

function app_main()
    println("LDGR $APP_VERSION (built $BUILT), Julia $(Base.VERSION)")
    flush(stdout)
    code = try
        start_app()
    catch e
        println("LDGR-FAIL ", sprint(showerror, e))
        flush(stdout)
        Base.display_error(stderr, e, catch_backtrace())
        1
    end
    flush(stdout)
    flush(stderr)
    exit(code)
end

end # module LDGR
