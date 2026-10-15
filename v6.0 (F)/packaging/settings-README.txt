LDGR settings folder
====================
For the technician. Clinic staff never need to open this folder.

WHAT THIS FOLDER IS
  The settings that belong to this computer. The program itself is in
  ..\runtime and is replaced by updates. This folder is never touched by
  an update.

  The books are in ..\Records. Do not edit or move anything there.
  The daily logs are in ..\logs (one file a day, kept for 60 days).
  Send the log for the day when reporting a problem.

notify.toml (EMAIL SETTINGS)
  Email is set up by hand at installation: put a file named notify.toml in
  this folder. An update will never overwrite or delete it.
  Use notify.example.toml from SolRegia as the starting point.

  The lines in notify.toml:
    to              Who receives the daily report (the owner's address).
    api_key         The Resend API key. It starts with "re_". It must be a
                    FULL ACCESS key, or an earlier version of a report
                    cannot be cancelled and the owner may get two.
    from            The sender, for example
                      "LDGR Daily Report <reports@clinic-domain.com>"
                    It MUST be an address on a domain verified in Resend.
                    Without it email stays off.
    subject_prefix  Text put in front of every subject line. Optional.
                    Safe to change.
    send_at         When the report goes out, on a 24-hour clock in this
                    computer's time, such as "17:30". Optional (17:30 if
                    left out). Safe to change, but keep the quotes, and
                    change the healthchecks.io schedule to match.

  Safe to change at any time: to, subject_prefix, send_at.
  Change with care: from and api_key (a wrong value stops email; the
  reason is written to ..\Records\audit_log.txt).

  Changes apply within about a minute. No restart is needed.

  To switch email off: close LDGR, then move or rename notify.toml (for
  example to notify.toml.off). The program works exactly as before, and
  just sends nothing. Put the name back to switch it on again.

KEEP THE API KEY SECRET
  The api_key can send email in the clinic's name. Never email the file,
  paste it into a chat, or show it on screen while others can see.
  Use a key made for this computer alone (name it after the PC), so it
  can be deleted in Resend without affecting anything else.

WATCHDOG (healthchecks.io)
  The program cannot tell you when a report fails to arrive. That is done
  outside this computer: a Resend webhook (event email.delivered) pings a
  healthchecks.io check with the schedule "30 17 * * 1-6", time zone
  America/Guyana, grace 1 to 2 hours. If send_at is changed, change that
  schedule to match. A new check does not watch until it has been pinged
  once: open its ping URL in a browser after setting it up.

ACCOUNT NAMES CANNOT BE CHANGED HERE
  In version 6.0 the account names used for QuickBooks are compiled into
  the program. They cannot be changed from this folder. A change needs a
  new build from SolRegia, installed with "Apply update.cmd" in ..\tools.
