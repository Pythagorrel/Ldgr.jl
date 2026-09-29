# A faster start

Julia compiles code the first time it runs it. For ldgr that means a wait when
the server starts and another the first time somebody presses Save, while
HTTP, JSON3, DataFrames and CSV are turned into machine code. The wait happens
again every time the server is restarted, because the work is thrown away when
the process ends.

A **system image** is that work saved to a file. `ldgr.dll` holds those four
packages already compiled, along with the code paths a normal day's entry uses.
Julia loads it instead of its own default image and skips the compiling.

**It is optional.** Nothing in the program looks for it. Without it the server
behaves exactly as before, only slower to start.

---

## Building it

Needs `PackageCompiler` in the default Julia environment, once:

```
julia -e 'using Pkg; Pkg.add("PackageCompiler")'
```

Then, from the `v4.0` folder:

```
julia --startup-file=no sysimage/build_sysimage.jl
```

It takes ten to twenty-five minutes and pins one processor core. It writes
`sysimage/ldgr.dll` (`.so` on Linux, `.dylib` on a Mac). The file is a few
hundred megabytes and is **not** kept in git — `.gitignore` in this folder
leaves it out. Every machine builds its own.

While it builds, `precompile_ldgr.jl` runs a whole day's entry against a
throwaway folder in the system temp directory, so the image also contains the
compiled form of the checks, the journal write and the ledger write. It then
does the same thing again over a real loopback socket, on a spare port the OS
picks, because otherwise HTTP.jl's server side — accepting the connection,
parsing the request, streaming the reply — would be left to compile on the
first request the browser makes. That throwaway folder is deleted at the end.
It never touches `Records/`.

## Starting the server with it

Double-click **`ldgr.bat`** in the `v4.0` folder. It uses the image when it is
there and falls back to plain Julia when it is not.

By hand, from `v4.0`:

```
julia -J sysimage/ldgr.dll --startup-file=no server.jl
```

Or from the Julia REPL:

```
julia -J sysimage/ldgr.dll
julia> include("server.jl")
julia> start()
```

Everything else is unchanged — the same port, the same window, the same books.

## When to build it again

The image holds a frozen copy of those four packages. Rebuild after:

- `Pkg.update()`, or installing a different version of HTTP, JSON3, DataFrames
  or CSV;
- upgrading Julia itself (an image built by one version will not load in
  another — Julia refuses it with a message about an incompatible system
  image);
- adding a package that `server.jl` uses, which also needs adding to the
  `PACKAGES` list in `build_sysimage.jl`.

**Editing `server.jl`, `Checks.jl`, `Config.jl` or any other `.jl` file in
`v4.0` does not need a rebuild.** Those files are not compiled into the image;
they are read from disk at every start, exactly as they always were. A stale
image is slower, never wrong.

If the image is ever suspect, delete `ldgr.dll` and start the server normally.
