# notices.jl - writes THIRD-PARTY-NOTICES.txt for the LDGR bundle.
#
#   julia --startup-file=no notices.jl <Manifest.toml> <output.txt> <OpenSSL artifact dir> <julia dir> <webview2 dir>
#
# Lists Julia, every non-stdlib package in the Manifest (with the licence files
# of its installed folder and of its _jll artifacts), the OpenSSL artifact and
# the WebView2 SDK, with full licence text.  A licence that cannot be found is
# listed as "licence file not found" and reported on stderr; it is never skipped.
# "MISSING:" lines are printed on stderr and the exit status is 1 when any licence
# is missing, so the build fails instead of shipping an incomplete notice file.

using TOML

const MANIFEST, OUT, OPENSSL_DIR, JULIA_DIR, WV2_DIR = ARGS

struct Entry
    name::String
    version::String
    where_::String          # where the licence text came from (for the reader)
    texts::Vector{Pair{String,String}}   # (file label => text)
    note::String
end

const LICENSE_RX = r"^(licen[sc]e|licen[sc]ing|copying|copyright|notice|unlicense)([._-].*)?$"i


function safe_read(path)
    b = read(path)
    s = String(copy(b))
    if !isvalid(s)   # Latin-1 fallback
        s = String(Char.(b))
    end
    startswith(s, "﻿") && (s = s[nextind(s, 1):end])
    return rstrip(replace(s, "\r\n" => "\n", "\r" => "\n"))
end

# Licence-looking files in a directory (non-recursive), or in a licenses/ folder.
function licence_files(dir)
    isdir(dir) || return String[]
    out = String[]
    for f in sort(readdir(dir))
        p = joinpath(dir, f)
        isfile(p) || continue
        stem = first(splitext(f))
        (occursin(LICENSE_RX, f) || occursin(LICENSE_RX, stem)) && push!(out, p)
    end
    return out
end

function licence_tree(dir)   # share/licenses/**: every file
    out = String[]
    isdir(dir) || return out
    for (root, _, files) in walkdir(dir), f in sort(files)
        push!(out, joinpath(root, f))
    end
    return sort(out)
end

depots() = [d for d in Base.DEPOT_PATH if isdir(d)]

function package_dir(name, uuid, sha)
    isempty(sha) && return nothing
    slug = Base.version_slug(Base.UUID(uuid), Base.SHA1(sha))
    for d in depots()
        p = joinpath(d, "packages", name, slug)
        isdir(p) && return p
    end
    return nothing
end

function artifact_dirs(pkgdir)
    out = String[]
    af = joinpath(pkgdir, "Artifacts.toml")
    isfile(af) || (af = joinpath(pkgdir, "JuliaArtifacts.toml"))
    isfile(af) || return out
    t = try TOML.parsefile(af) catch; return out end
    function visit(x)
        if x isa Dict
            if haskey(x, "git-tree-sha1")
                h = x["git-tree-sha1"]
                for d in depots()
                    p = joinpath(d, "artifacts", h)
                    isdir(p) && !(p in out) && push!(out, p)
                end
            else
                foreach(visit, values(x))
            end
        elseif x isa Vector
            foreach(visit, x)
        end
    end
    foreach(visit, values(t))
    return sort(out)
end

function guess_type(texts)
    s = join(last.(texts), "\n")
    l = lowercase(s)
    found = String[]
    occursin("gnu lesser general public license", l) || occursin("gnu library general public", l) ? push!(found, "LGPL") : nothing
    if occursin("gnu general public license", l) && !(occursin("lesser general public", l) && !occursin("version 3, 29 june 2007", l))
        push!(found, "GPL")
    end
    occursin("apache license", l) && occursin("version 2.0", l) && push!(found, "Apache-2.0")
    occursin("mozilla public license", l) && push!(found, "MPL")
    occursin("permission is hereby granted, free of charge", l) && push!(found, "MIT")
    if occursin("redistribution and use in source and binary forms", l)
        push!(found, occursin("neither the name", l) || occursin("endorse or promote", l) ? "BSD-3-Clause" : "BSD-2-Clause")
    end
    occursin("openssl", l) && occursin("apache", l) && !("Apache-2.0" in found) && push!(found, "Apache-2.0")
    (occursin("isc license", l) || occursin("permission to use, copy, modify, and/or distribute this software for any", l)) && push!(found, "ISC")
    occursin("this is free and unencumbered software", l) && push!(found, "Unlicense")
    occursin("zlib license", l) || occursin("altered source versions must be plainly marked", l) ? push!(found, "zlib") : nothing
    occursin("microsoft software license terms", l) && push!(found, "Microsoft (see text)")
    isempty(found) && return "other (see text)"
    return join(unique(found), " + ")
end

function main()
man0 = TOML.parsefile(MANIFEST)
man_deps = man0["deps"]
entries = Entry[]
missing_list = String[]

# ---- (1) Julia ----------------------------------------------------------
begin
    texts = Pair{String,String}[]
    jl = joinpath(JULIA_DIR, "LICENSE.md")
    isfile(jl) && push!(texts, "LICENSE.md" => safe_read(jl))
    extra = String[]
    for rel in ("share/julia/base/ryu/LICENSE.md", "share/julia/base/JuliaSyntax/LICENSE.md")
        p = joinpath(JULIA_DIR, rel)
        isfile(p) && push!(texts, rel => safe_read(p))
    end
    for p in licence_tree(joinpath(JULIA_DIR, "share", "licenses"))
        push!(texts, relpath(p, JULIA_DIR) => safe_read(p))
    end
    stdlib = joinpath(JULIA_DIR, "share", "julia", "stdlib")
    if isdir(stdlib)
        for (root, _, files) in walkdir(stdlib), f in sort(files)
            occursin(LICENSE_RX, f) || occursin(LICENSE_RX, first(splitext(f))) || continue
            p = joinpath(root, f)
            push!(texts, "stdlib: " * relpath(p, stdlib) => safe_read(p))
        end
    end
    isempty(texts) && push!(missing_list, "Julia: no licence files under $JULIA_DIR")
    note = """
Julia is distributed with the following bundled third-party libraries, whose licence texts are NOT shipped as separate files in the Julia distribution. They are listed here with their licences; their source code is available from the upstream projects named below and, as the versions Julia 1.10.12 uses, from https://github.com/JuliaLang/julia/tree/v1.10.12 (see its deps/ folder). The file THIRDPARTY.md, which the Julia licence text below refers to, is not shipped with this bundle; it is at https://github.com/JuliaLang/julia/blob/v1.10.12/THIRDPARTY.md. This list was written by hand for Julia 1.10.12, not generated from the install. The LGPL and GPL components can be replaced by the user with a compatible build of the same library.

  libuv ................ MIT         https://github.com/libuv/libuv
  LLVM (incl. libLTO, libRemarks) ... Apache-2.0 with LLVM exceptions   https://llvm.org
  libunwind ............ MIT         https://github.com/libunwind/libunwind
  PCRE2 ................ BSD-3-Clause   https://github.com/PCRE2Project/pcre2
  OpenLibm ............. MIT and BSD (FreeBSD msun, Sun Microsystems)   https://github.com/JuliaMath/openlibm
  utf8proc ............. MIT         https://github.com/JuliaStrings/utf8proc
  dSFMT ................ BSD-3-Clause   https://github.com/MersenneTwister-Lab/dSFMT
  Ryu .................. Apache-2.0 or Boost-1.0   https://github.com/ulfjack/ryu
  GMP .................. LGPL-3.0-or-later or GPL-2.0-or-later (dual)   https://gmplib.org
  MPFR ................. LGPL-3.0-or-later   https://www.mpfr.org
  libgit2 .............. GPL-2.0 with linking exception   https://github.com/libgit2/libgit2
  LibSSH2 .............. BSD-3-Clause   https://libssh2.org
  curl ................. curl licence (MIT-style)   https://curl.se
  mbedTLS .............. Apache-2.0 (or GPL-2.0-or-later)   https://github.com/Mbed-TLS/mbedtls
  zlib ................. zlib licence   https://zlib.net
  OpenBLAS ............. BSD-3-Clause   https://github.com/OpenMathLib/OpenBLAS
  LAPACK (reference) ... BSD-3-Clause (modified BSD)   https://www.netlib.org/lapack
  libblastrampoline .... MIT         https://github.com/JuliaLinearAlgebra/libblastrampoline
  SuiteSparse .......... mixed: BSD-3-Clause, LGPL-2.1+ and GPL-2.0+ parts   https://github.com/DrTimothyAldenDavis/SuiteSparse
  nghttp2 .............. MIT         https://github.com/nghttp2/nghttp2
  libwhich ............. MIT         https://github.com/vtjnash/libwhich
  p7zip ................ LGPL-2.1+ with unRAR restriction   https://github.com/p7zip-project/p7zip
  Mozilla CA bundle .... MPL-2.0     https://curl.se/docs/caextract.html
  MinGW-w64 / GCC runtime libraries (libgcc, libstdc++, libgfortran, libquadmath, libgomp, libatomic, libssp, libwinpthread) ..... GPL-3.0 with GCC Runtime Library Exception, LGPL; winpthreads MIT-style   https://gcc.gnu.org, https://www.mingw-w64.org

The Julia standard-library packages (Pkg, Tar, Downloads, SHA, Statistics, SparseArrays, ...) ship inside Julia and are covered by its MIT licence unless a licence file is reproduced below."""
    push!(entries, Entry("Julia", "1.10.12", "Julia distribution ($(basename(JULIA_DIR)))", texts, note))
end

# ---- (2) Manifest packages ------------------------------------------------
man = man0
deps = man["deps"]
npkg = 0; nstd = 0
for name in sort(collect(keys(deps)))
    name == "LDGR" && continue
    rec = deps[name][1]
    sha = get(rec, "git-tree-sha1", "")
    if isempty(sha)
        nstd += 1          # standard library: ships inside Julia
        continue
    end
    npkg += 1
    ver = get(rec, "version", "unknown")
    dir = package_dir(name, rec["uuid"], sha)
    texts = Pair{String,String}[]
    where_ = "package folder not found"
    if dir === nothing
        push!(missing_list, "$name $ver: installed folder not found in depot")
    else
        where_ = dir
        for p in licence_files(dir)
            push!(texts, basename(p) => safe_read(p))
        end
        if isempty(texts)   # a few packages keep it one level down
            for sub in ("docs", "doc", "license", "licenses", "LICENSES")
                for p in licence_files(joinpath(dir, sub))
                    push!(texts, sub * "/" * basename(p) => safe_read(p))
                end
            end
        end
        if endswith(name, "_jll")
            for a in artifact_dirs(dir)
                for p in licence_tree(joinpath(a, "share", "licenses"))
                    push!(texts, "artifact " * basename(a)[1:8] * ": " * relpath(p, joinpath(a, "share", "licenses")) => safe_read(p))
                end
            end
        end
    end
    note = ""
    if isempty(texts)
        push!(missing_list, "$name $ver: licence file not found" * (dir === nothing ? "" : " in $dir"))
        note = "licence file not found"
    end
    push!(entries, Entry(name, ver, where_, texts, note))
end

# ---- (3) OpenSSL artifact --------------------------------------------------
begin
    texts = Pair{String,String}[]
    ld = joinpath(OPENSSL_DIR, "share", "licenses")
    for p in licence_tree(ld)
        push!(texts, relpath(p, ld) => safe_read(p))
    end
    note = ""
    isempty(texts) && (push!(missing_list, "OpenSSL artifact: no licence files in $ld"); note = "licence file not found")
    # OpenSSL_jll is already in the package list; this is the library itself.
    ver = get(get(get(man_deps, "OpenSSL_jll", [Dict()]), 1, Dict()), "version", "unknown")
    push!(entries, Entry("OpenSSL (library, from OpenSSL_jll artifact)", ver, OPENSSL_DIR, texts, note))
end

# ---- (4) WebView2 -----------------------------------------------------------
begin
    texts = Pair{String,String}[]
    for f in ("LICENSE.txt", "NOTICE.txt")
        p = joinpath(WV2_DIR, f)
        isfile(p) ? push!(texts, f => safe_read(p)) : push!(missing_list, "WebView2: $f not found in $WV2_DIR")
    end
    note = isempty(texts) ? "licence file not found" : ""
    push!(entries, Entry("Microsoft WebView2 SDK", "see note", WV2_DIR, texts, note * (isempty(note) ? "" : "
") * "Version: the WebView2 SDK files shipped in the webview2 folder of this bundle (loader DLL); Microsoft does not state a version in LICENSE.txt or NOTICE.txt."))
end

# ---- write ------------------------------------------------------------------
io = IOBuffer()
bar = "="^78
println(io, bar)
println(io, "LDGR 6.0 - THIRD-PARTY SOFTWARE NOTICES")
println(io, bar)
println(io)
println(io, "LDGR itself is the work of SolRegia and is NOT covered by any of the licences")
println(io, "below. This file lists the third-party software that is included in, or runs")
println(io, "together with, LDGR, with the licence text of each as supplied by its authors.")
println(io, "The Julia standard libraries ship inside Julia and are covered by its entry.")
println(io, "The licence column is a keyword guess for orientation only. Julia contains LGPL")
println(io, "and GPL components (listed in its entry); WebView2 uses Microsoft's own licence")
println(io, "terms. The full texts below are authoritative.")
println(io)
println(io, "CONTENTS ($(length(entries)) entries; $npkg packages from the build's Manifest, $nstd standard libraries covered by Julia)")
println(io)
println(io, rpad("No.", 5), rpad("Name", 52), rpad("Version", 14), "Licence (indicative)")
println(io, "-"^100)
for (i, e) in enumerate(entries)
    lic = isempty(e.texts) ? "licence file not found" : guess_type(e.texts)
    println(io, rpad(string(i), 5), rpad(first(e.name, 50), 52), rpad(e.version, 14), lic)
end
println(io)
for (i, e) in enumerate(entries)
    println(io, bar)
    println(io, "[$i] ", e.name, isempty(e.version) ? "" : "  version " * e.version)
    println(io, bar)
    if isempty(e.texts)
        println(io, "licence file not found")
    end
    isempty(e.note) || e.note == "licence file not found" || (println(io, e.note); println(io))
    for (label, t) in e.texts
        println(io, "--- ", label, " ---")
        println(io, t)
        println(io)
    end
end
text = String(take!(io))
text = replace(text, "\r\n" => "\n")
text = replace(text, "\n" => "\r\n")
mkpath(dirname(abspath(OUT)))
write(OUT, text)

println("notices: wrote $OUT ($(filesize(OUT)) bytes), $(length(entries)) entries, $npkg packages, $nstd stdlib skipped")
for m in missing_list
    println(stderr, "MISSING: ", m)
end
isempty(missing_list) || exit(1)
end

main()
