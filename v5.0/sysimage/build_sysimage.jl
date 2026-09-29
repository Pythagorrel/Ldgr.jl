# =============================================================================
# build_sysimage.jl — builds sysimage/ldgr.dll (.so, .dylib elsewhere).
#
# RUN IT (either of these works; paths are worked out from this file):
#     julia --startup-file=no sysimage/build_sysimage.jl        from v4.0/
#     julia --startup-file=no build_sysimage.jl                 from sysimage/
#
# It takes ten to twenty-five minutes and pins one core. Nothing else needs to
# be running.
#
# WHAT IT DOES: compiles HTTP, JSON3, DataFrames and CSV — the four packages the
# server waits on — into a Julia system image, and while doing so watches
# precompile_ldgr.jl run a whole day's entry so the code paths that day uses are
# compiled as well. Dates, Logging and Sockets are standard library and come
# along on their own.
#
# WHAT IT DOES NOT DO: it does not compile server.jl or the bookkeeping files
# into the image. They are read from disk as usual at every start, so editing
# them needs no rebuild. See sysimage/README.md for when a rebuild IS needed.
# =============================================================================

using Libdl, Dates

const HERE    = @__DIR__
const V40     = normpath(joinpath(HERE, ".."))
const OUT     = joinpath(HERE, "ldgr." * Libdl.dlext)
const EXECFILE = joinpath(HERE, "precompile_ldgr.jl")
const PACKAGES = [:HTTP, :JSON3, :DataFrames, :CSV]

isfile(EXECFILE) || error("Cannot find $EXECFILE")
isfile(joinpath(V40, "server.jl")) || error("Cannot find server.jl beside $HERE")

println()
println("  Building the ldgr system image")
println("  ------------------------------")
println("  Julia            : ", VERSION)
println("  Packages         : ", join(PACKAGES, ", "))
println("  Warm-up script   : ", EXECFILE)
println("  Writing to       : ", OUT)
println("  Started          : ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))
println()
println("  This takes ten to twenty-five minutes. Leave it alone.")
println()
flush(stdout)

import PackageCompiler

t0 = time()
PackageCompiler.create_sysimage(
    PACKAGES;
    sysimage_path             = OUT,
    precompile_execution_file = EXECFILE,
)
elapsed = time() - t0

mb(path) = round(filesize(path) / 1024^2, digits = 1)

println()
println("  Done in ", round(Int, elapsed ÷ 60), " min ", round(Int, elapsed % 60), " s")
println("  ", OUT, "  (", mb(OUT), " MB)")
println()
println("  Start the server with it:")
println("      julia -J ", relpath(OUT, V40), " --startup-file=no server.jl")
println("  or just double-click ldgr.bat in the v4.0 folder.")
println()
