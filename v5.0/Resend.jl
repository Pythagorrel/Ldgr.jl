module Resend

using HTTP, JSON3, Dates

# =============================================================================
# RESEND — the email service the daily report is handed to.
#
# WHAT THIS FILE IS: a small HTTP client for two calls of Resend's API, and
# nothing else. It knows how to ask Resend to send (or to send later) one email,
# and how to cancel one that has not gone yet. It knows nothing about ldgr — not
# what a report is, not when one is due, not where anything is kept. All of that
# is Notify.jl's business, which is why Notify.jl can be tested with a fake in
# this module's place and this module can be tested against a stub server with
# no books at all.
#
# WHY RESEND AND NOT THE CLINIC'S OWN MAILBOX. The first version of the daily
# report signed in to Gmail over SMTP with an app password. Google revoked the
# password a day after it first worked and nothing said so for a week. SMTP also
# sends only now, which needs the program running at the send time — and ldgr is
# normally opened at closing time, used for a few minutes and closed again.
# Resend holds a message and sends it at a time given in advance
# (`scheduled_at`), so the report can be handed over while ldgr is open and
# still go out at the fixed hour after it has been closed.
#
# LOADED BY server.jl, NOT BY main.jl. HTTP.jl takes seconds to load without the
# system image, and the command line (main.jl) never sends anything: a day typed
# there is picked up by the next server start. So nothing that only includes
# main.jl pays for this file.
#
# EVERY FAILURE IS ONE PLAIN SENTENCE, sorted into one of two kinds (`Failure`):
#   :settings   a person has to fix notify.toml or the Resend account. Trying
#               again in five minutes will fail the same way.
#   :temporary  the internet, or Resend, is not answering properly just now.
#               Trying again later is the whole remedy.
# The caller decides how long to wait from the kind; the words go to the audit
# log and the terminal as they are.
#
# THE API KEY NEVER APPEARS IN ANY TEXT THIS FILE BUILDS. It is put in one
# request header and nowhere else. HTTP.jl's own errors can print the whole
# request, headers and all, so they are never shown: each is turned into a
# sentence written here, and every sentence is scrubbed of the key once more
# before it leaves, in case a future edit gets that wrong.
# =============================================================================

"""
    API_BASE[]

Where Resend's API is. A `Ref` so the tests can point it at a stub server on
127.0.0.1 and never reach the real service.
"""
const API_BASE = Ref("https://api.resend.com")

"""
    TIMEOUTS[]

How long to wait, in whole seconds: `connect` for the connection to open, `read`
for an answer once it has. Without them a dead connection could hold the report
for as long as the operating system cares to wait. A `Ref` so the tests can
shorten them.
"""
const TIMEOUTS = Ref((connect = 10, read = 30))

"""
    Failure(kind, words[, reached])

Why a call to Resend did not work. `kind` is `:settings` (somebody must fix
notify.toml or the Resend account) or `:temporary` (try again later). `words`
is one plain sentence, already free of the API key, fit for the audit log.

`reached` is false only when the request certainly never left this computer —
the name could not be looked up, the connection was refused or never opened,
the secure connection could not be set up. Then Resend cannot have made
anything, and the caller need not ask it again about this request. Every other
failure (no answer in time, a connection cut off, any answer at all) leaves
`reached` true: Resend may have made the email.
"""
struct Failure <: Exception
    kind::Symbol
    words::String
    reached::Bool
end
Failure(kind::Symbol, words::AbstractString) = Failure(kind, String(words), true)
Base.showerror(io::IO, f::Failure) = print(io, f.words)

# --- The two calls ----------------------------------------------------------

"""
    send(key, email; idempotency_key) -> id::String

Hand one email to Resend (`POST /emails`) and return the id Resend gave it.

`email` is the JSON body as a dictionary: `from`, `to` (a list), `subject`,
`text`, `html` when the message has an HTML version beside its plain text, and
`scheduled_at` when the message is to wait until a given moment. It is passed
to Resend as it stands: nothing here reads or changes the body.

`idempotency_key` makes a repeat harmless. If the reply to a request is lost
and the same request is sent again with the same key, Resend answers with the
email it already made instead of making a second one. The caller builds the key
from the content, so only an identical request can ever share it.

Throws a `Failure` for anything but success.
"""
function send(key::AbstractString, email::AbstractDict; idempotency_key::AbstractString)
    _need_key(key)
    headers = ["Authorization"   => "Bearer " * key,
               "Content-Type"    => "application/json",
               "Idempotency-Key" => String(idempotency_key),
               "User-Agent"      => "ldgr"]
    status, body = _call("POST", "/emails", headers, JSON3.write(email), key)
    if 200 <= status < 300
        name, message, id = _fields(body)
        isempty(id) && throw(Failure(:temporary, _scrub(
            "Resend accepted the report but did not say what it called it, so it will be handed over again.", key)))
        return id
    end
    throw(_failure(status, body, key))
end

"""
    cancel(key, id) -> nothing

Cancel an email Resend is still holding (`POST /emails/{id}/cancel`).

AN EMAIL THAT CANNOT BE FOUND OR IS NO LONGER WAITING IS NOT A FAILURE. What
happens when a message that has already gone is cancelled is not documented;
whatever Resend says about it, there is nothing left to cancel, which is the
outcome the caller wanted. So a 404, or any other 4xx that is not about the key
(401, 403), the rate (429) or a request that timed out (408), returns normally.
Everything else — those four, a 5xx, and anything that is not a 4xx at all,
such as a redirect — throws, so an earlier version is never recorded as
cancelled when Resend did not say so.
"""
function cancel(key::AbstractString, id::AbstractString)
    _need_key(key)
    headers = ["Authorization" => "Bearer " * key,
               "User-Agent"    => "ldgr"]
    status, body = _call("POST", "/emails/$(HTTP.escapeuri(String(id)))/cancel", headers, "", key)
    200 <= status < 300 && return nothing
    (400 <= status < 500 && !(status in (401, 403, 408, 429))) && return nothing
    throw(_failure(status, body, key))
end

# --- The request ------------------------------------------------------------

function _need_key(key::AbstractString)
    isempty(strip(key)) &&
        throw(Failure(:settings, "notify.toml has no Resend api_key, so nothing could be handed to Resend."))
    return nothing
end

"""
    _call(method, path, headers, body, key) -> (status, body)

One request, with every safety catch on: a deadline for connecting and for the
answer, no automatic retry (the caller retries, on its own timetable, with the
same idempotency key), no following redirects (a redirect would carry the key
somewhere it was not meant to go), and no exception for a status — a 4xx is an
answer to be read, not a crash.

Anything that goes wrong before an answer arrives becomes a `:temporary`
failure with a sentence written here, never HTTP.jl's own text, which can
include the request headers and therefore the key.
"""
function _call(method::String, path::String, headers, body::String, key::AbstractString)
    url = API_BASE[] * path
    t = TIMEOUTS[]
    resp = try
        HTTP.request(method, url, headers, body;
                     connect_timeout = t.connect, readtimeout = t.read,
                     retry = false, status_exception = false, redirect = false)
    catch e
        throw(Failure(:temporary, _scrub(_network_words(e), key), !_before_sending(e)))
    end
    return (Int(resp.status), String(copy(resp.body)))
end

"""
    _before_sending(e) -> Bool

Did this fail before a byte of the request was sent? HTTP.jl reports every
failure to look up the name, open the connection or set up the secure
connection as a `ConnectError` (sometimes inside a `RequestError`); anything
else happened after the request went.
"""
_before_sending(e) = e isa HTTP.Exceptions.ConnectError ||
                     (e isa HTTP.Exceptions.RequestError && e.error isa HTTP.Exceptions.ConnectError)

"""
    _network_words(e) -> String

What went wrong on the way to Resend, in one sentence. Only the kind of fault is
named — never the exception's own text, for the reason in `_call`.
"""
function _network_words(e)
    # HTTP.jl wraps the real cause, often several layers deep: a RequestError
    # or a ConnectError around a CapturedException around (say) a DNS error,
    # or a RequestError around a CompositeException around a failed task
    # around the EOFError of a reply that was cut off.
    inner = e
    for _ in 1:8
        if inner isa HTTP.Exceptions.RequestError || inner isa HTTP.Exceptions.ConnectError
            inner = inner.error
        elseif inner isa CapturedException
            inner = inner.ex
        elseif inner isa CompositeException && !isempty(inner.exceptions)
            inner = first(inner.exceptions)
        elseif inner isa TaskFailedException
            inner = inner.task.exception
        else
            break
        end
    end
    kind = nameof(typeof(inner))

    # A CERTIFICATE THAT COULD NOT BE CHECKED IS NOT "NO INTERNET". It is
    # usually the computer's clock being wrong, or antivirus software that
    # inspects secure connections by re-signing them, and saying "the internet
    # could not be reached" would send whoever reads the log to check a
    # connection that works. OpenSSL's own words name the certificate problem
    # and come from its error queue, never from the request, so they are safe
    # to quote.
    if kind in (:OpenSSLError, :MbedException)
        detail = _shorten(hasproperty(inner, :msg) ? string(getproperty(inner, :msg)) :
                          first(split(sprint(showerror, inner), '\n')))
        return "The secure (HTTPS) connection to Resend could not be checked ($(detail)). Make sure " *
               "the computer's date and time are right and that antivirus software is not " *
               "inspecting secure connections. The report will be handed over again in a few minutes."
    end

    connect = e isa HTTP.Exceptions.ConnectError ||
              (e isa HTTP.Exceptions.RequestError && e.error isa HTTP.Exceptions.ConnectError)
    timeout = e isa HTTP.Exceptions.TimeoutError || inner isa HTTP.Exceptions.TimeoutError ||
              kind === :TimeoutException
    what = if occursin("DNSError", string(typeof(inner)))
        "the name api.resend.com could not be looked up, which usually means there is no internet"
    elseif connect && timeout
        "the connection could not be opened within $(TIMEOUTS[].connect) seconds"
    elseif connect
        "the connection could not be opened"
    elseif timeout
        "no answer came within $(TIMEOUTS[].read) seconds"
    elseif inner isa EOFError || inner isa Base.IOError
        "the connection was cut off"
    else
        "the request failed ($(nameof(typeof(inner))))"
    end
    return "The internet or Resend could not be reached: $(what). The report will be handed over again in a few minutes."
end

# --- Reading Resend's answer ------------------------------------------------

"""
    _fields(body) -> (name, message, id)

The three things this program ever reads from a reply, each `""` when absent.

READ DEFENSIVELY. Resend's errors are JSON, roughly `{"statusCode", "name",
"message"}`, but a proxy, a captive portal or an outage page can answer with
anything at all. Nothing here throws, and nothing that is not JSON is quoted
back.
"""
function _fields(body::AbstractString)
    obj = try
        JSON3.read(body)
    catch
        return ("", "", "")
    end
    obj isa AbstractDict || return ("", "", "")
    s(k) = (v = get(obj, k, nothing); v isa AbstractString ? String(v) : "")
    return (s(:name), s(:message), s(:id))
end

"""
    _failure(status, body, key) -> Failure

A refusal from Resend as one sentence and a kind.

The sentences say what to DO, because the person reading the audit log is
setting the program up, not debugging it. Resend's own message is quoted where
no sentence here fits, cut short and scrubbed of the key.
"""
function _failure(status::Int, body::AbstractString, key::AbstractString)
    name, message, _ = _fields(body)
    # Scrubbed BEFORE it is cut short: a key that straddled the cut would
    # otherwise survive as a prefix the scrub no longer recognises.
    said = isempty(message) ? "" : " Resend said: \"$(_shorten(_scrub(message, key)))\""
    low = lowercase(message)
    f = if status == 401 && name == "restricted_api_key"
        Failure(:settings,
            "The Resend API key in notify.toml can only send; make a Full access key so an " *
            "earlier version of the report can be cancelled.")
    elseif status == 401 || (status == 403 && (name == "invalid_api_key" || occursin("api key", low)))
        Failure(:settings,
            "Resend did not accept the api_key in notify.toml (it is missing, wrong or suspended). " *
            "Make a new Full access key in Resend and paste it into notify.toml.")
    elseif status == 403 && (occursin("testing emails", low) || occursin("own email", low))
        Failure(:settings,
            "Resend only sends to the address the Resend account was opened with; " *
            "`to` in notify.toml must be that address.")
    elseif status == 403 && occursin("domain", low)
        Failure(:settings,
            "Resend will not send from the address in `from`: its domain is not verified in the " *
            "Resend account. Verify the domain in Resend (Domains), or put an address on a " *
            "verified domain in `from` in notify.toml.$(said)")
    elseif status == 403
        Failure(:settings, "Resend refused the report (403). Check api_key, `to` and `from` in notify.toml.$(said)")
    elseif status == 409
        Failure(:temporary, "Resend was still working on an earlier attempt at the same report (409); it will be tried again.$(said)")
    elseif status == 429
        Failure(:temporary,
            "Resend's sending limit has been reached$(isempty(name) ? "" : " ($(name))"); " *
            "the report will be tried again later.")
    elseif status >= 500
        Failure(:temporary, "Resend is having trouble ($(status)); the report will be tried again in a few minutes.")
    elseif status in (400, 404, 422)
        Failure(:settings, "Resend refused the report ($(status)). Check `to` and `from` in notify.toml.$(said)")
    else
        Failure(:temporary, "Resend answered with an unexpected status ($(status)); the report will be tried again.$(said)")
    end
    return Failure(f.kind, _scrub(f.words, key))
end

_shorten(s::AbstractString) = (t = strip(replace(s, r"\s+" => " ")); length(t) > 200 ? first(t, 197) * "..." : String(t))

"""
    _scrub(text, key) -> String

`text` with the key taken out, if it is somehow in there. Belt and braces: no
sentence in this file puts it there, and this makes sure no future one does. A
key too short to be real is left alone rather than blanking every letter it
happens to match. Anything else shaped like a Resend key (`re_` and at least
eight more letters, digits or underscores) is masked too — a key cut short, or
an old key that notify.toml no longer holds. Resend's email ids are plain
UUIDs, so none is caught by it.
"""
function _scrub(text::AbstractString, key::AbstractString)
    t = length(key) >= 8 ? replace(String(text), String(key) => "********") : String(text)
    return replace(t, KEY_SHAPE => "********")
end

"What a Resend API key looks like, for `_scrub`."
const KEY_SHAPE = r"\bre_[A-Za-z0-9_]{8,}"

end # module Resend
