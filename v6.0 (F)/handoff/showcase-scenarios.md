# Showing ldgr to an audience

A six day script for the entry form. Follow it by hand, in order, and the audience
sees every check, every warning, every tip, the first day tick box, an Off day, a missing
day, a saved day corrected, and what a save writes. Nothing here needs the command line.

Everything typed is a round figure. The differences that come out of them are
whatever the arithmetic gives.

Verified end to end on 2026-09-15 against the working tree, and again on
2026-09-16 after the money format in the report, the date wording in two notices,
the first day tick box and the new reminder on a gap filler were changed. Every
sentence quoted in this document is the program's own wording, taken from the
running server or from the form in Chrome. Passages marked 2026-10-07 (a saved
day coming up by itself, the link after Clear, Ctrl+Alt+Z, the Off day's grey
note) were written from the code and the browser scripts of that day, not from
a fresh run of this script.

---

## Before you start

### 1. Point the program at a scratch folder

The demo writes real files. Send them somewhere disposable, never to
`v4.0\Records`, which holds the real books.

**The folder must be empty when you begin.** Day 1 has to be the first day on
record. If you run the demo twice, empty the folder (or pick a new one) first.

**PowerShell**, from `E:\Ldgr\v4.0`:

```powershell
$env:LEDGER_ROOT = "C:\ldgr-demo"
julia --startup-file=no server.jl 8765
```

**Git Bash**, from `E:\Ldgr\v4.0`:

```bash
LEDGER_ROOT="C:/ldgr-demo" julia --startup-file=no server.jl 8765
```

**With the system image** (checked: `ldgr.bat` changes directory and hands the
port through, it does not touch `LEDGER_ROOT`, so the variable you set is the one
it uses). Set the variable first, then:

```powershell
$env:LEDGER_ROOT = "C:\ldgr-demo"
.\ldgr.bat 8765
```

The window opens by itself, maximized and at 100% zoom. The server warms itself up before it starts
listening: about 11 seconds on plain Julia, about 2 seconds with the system
image, plus a few seconds for Julia to load first. Wait until the terminal says
`Ready` before you touch anything. After that every screen answers at once.

If you would rather open the page yourself, set `LDGR_NO_BROWSER=1` as well and
go to <http://127.0.0.1:8765>.

As it starts, the terminal window prints `Records folder :` and the path it is
using. Read that line out loud once. It is the easiest way to show an audience
that the real books are not involved.

### 2. Pick the dates

Pick six consecutive calendar dates ending on or before the day you demo. **Make
Day 6 the day you are demonstrating**, because the last step shows what Next day
says when there is no next day yet. The date picker only offers the current year
and the two before it, so the block has to sit inside those three years.

| In this document | Means |
|---|---|
| Day 1 | five days before the demo |
| Day 2 | four days before |
| Day 3 | three days before |
| Day 4 | two days before |
| Day 5 | the day before |
| Day 6 | the day of the demo |

Day 5 is entered **out of order**, after Day 6. That is deliberate.

Six dates inside one calendar month make the tidiest demo, because everything
then lands in one Daily Journal.

There is no weekday rule anywhere in the program, so Day 3 works as the clinic's
day off whatever day of the week it lands on.

### 3. Learn the four words

The Checks panel on the right labels every line with one of four words. That is
the whole vocabulary:

| Word | What it means |
|---|---|
| **Must fix** | the day cannot be saved at all |
| **Needs a reason** | the day can be saved, but only with a typed explanation |
| **Good to know** | nothing to do, just something to be aware of |
| **Tip** | a guess at what caused a difference |

### 4. The shape of the screen

Three numbered cards down the middle: **1 Start of day** (the date, the work
day / off day switch, the counted opening balance), **2 Today's numbers**, and
**3 End of day** (the counted closing balance). Below them is the dock, which
holds the first day tick box when it is needed, the running totals (Takings,
Expenses, Banked) and the buttons: Clear, Save and Next day. The Checks panel is
the column on the right.

The header says **LDGR**, with the caption Urgent Care. Four keyboard shortcuts
exist, and only four: **Ctrl+S** is Save, **Ctrl+N** is Next day,
**Ctrl+Alt+C** is Clear, and **Ctrl+Alt+Z** presses "Show saved figures"
(2026-10-07), which is there only after Clear on a saved day ("Day 6 again"
shows it). Each does exactly what its button does, refusals included.
Hovering over a button, or over that link, shows its shortcut.

Nothing floats. The Checks panel and the dock sit in the page, so they never
cover a box somebody is typing in.

---

## The six days at a glance

| Day | Kind of day | What the audience sees |
|---|---|---|
| 1 | First day on record | The three things that stop a save: a stray third decimal, a deposit bigger than the cash there was, a balance left blank. Then a difference, a tip that finds it, a clean day, the first day tick box, and the ledger notice that appears once a day has been saved. |
| 2 | Ordinary day | Nothing to fix. The difference between Save and Next day: Next day refuses to move on from a day that is not in the books. |
| 3 | Off day | The clinic was shut. No figures, no ledger, the balance carried through. |
| 4 | Two differences | The opening does not match last night, and the day does not balance. Two separate reason boxes. One reason does not cover the other. |
| 5 | Missing day, filled in last | A decimal point in the wrong place, and a reminder to check the day above it. Entering it releases Day 6's held ledger. |
| 6 | The demo day | A ledger waiting on the missing day before it. Two swapped digits. Then the saved day coming back by itself when its date is picked, Clear and Show saved figures (optional), the day corrected, its ledger regenerated, and Next day with nowhere to go. |

---

## Day 1: the first day on record

Type this by the end of the day. The steps below get there through three
deliberate mistakes.

| Box | Type |
|---|---|
| Opening Balance | 20000 |
| Cash Sales | 60000 |
| POS Deposits To Scotiabank | 15000 |
| Doctor's Fees | 10000 |
| Medical Supplies | 5000 |
| Taxi Fare | 2000 |
| Deposits | 40000 at first, then cleared (step 7) |
| Closing Balance | 63000 |

### Step 1: the date

Pick Day 1 in the three date selects.

Under the Opening Balance box:

> This would be the first day on record. Its opening balance cannot be checked
> against anything.

And a tick box appears in the dock:

> This is the **first day on record**. Accept its opening balance as the starting
> point.

**Save is greyed out.** It stays greyed out until that box is ticked. The
program will not accept a starting balance it cannot check against unless
somebody says so on purpose.

The Checks panel says **Nothing to fix so far**.

### Step 2: the opening count

Type `20000` in Opening Balance and move on. Nothing happens, and that is the
point: there is nothing to compare it against yet.

### Step 3: a stray third decimal (a save the program will not allow)

Type the day's figures, Deposits included, but type Taxi Fare as `2000.005` (an
extra key press after the cents). Leave the Closing Balance box alone for now.

The instant the box is typed in, under the box:

> At most two decimal places.

The box turns red and **Save greys out**. The Checks panel gets one line:

> **Not a valid amount** · Must fix · Taxi Fare

Press **See full explanation** on that line. It opens in the dock, just above
the buttons:

> "Taxi Fare" has more than two decimal places. Cash cannot be smaller than a
> cent.

Correct it to `2000`. The red goes, the line goes, Save comes back.

Worth saying out loud: the message under the box is the browser being helpful;
the line in the Checks panel is the server having checked the same thing for
itself. The browser never decides how serious anything is.

### Step 4: a balance left blank (Save stays grey)

Click into the Closing Balance box and leave it without typing. Now:

> **Closing Balance Not Entered** · Must fix

Note the timing. The warning did not appear while the box was still untouched.
The program does not tell anybody off for a box they have not got to yet.
*(Front-end behaviour, read from app.js: a Must fix about a drawer count is held
back from the Checks panel while that box is blank and has not been left, and a
difference in one waits for the same moment. Save is grey all the same: since
2026-10-06 the button follows the server's check, shown row or not.)*

Now tick the first day box in the dock. **Save stays greyed out.** Point at the
Must fix line: that is why. Nothing with a Must fix on it can be saved, and the
button says so before anybody presses it. *(Before 2026-10-06 Save turned green
here and the press was refused with "This day cannot be saved yet."; the owner
asked for the button to be grey instead.)*

Press the grey Save anyway. Nothing is sent, but the program still answers.
The banner at the top of the page:

> This day cannot be saved yet.

And the program's own words open in the dock, right above the button that was
pressed (the same as **See full explanation** on that line):

> "Closing Balance" has not been filled in. Blank is not the same as zero here.
> Enter 0 only if it really was empty.

This is the distinction the whole check exists for. Blank means nobody counted.
Zero means somebody counted and the drawer was empty. One of those is a fact.

The ✕ on that line only closes the line. Leave it or close it, either is fine.

### Step 5: a deposit bigger than the cash there was

Leave the closing balance blank for one more moment. Change Deposits from
`40000` to `400000` (one zero too many, the commonest possible slip).

A second line joins the first, so the panel now reads:

> **Closing Balance Not Entered** · Must fix
> **Expenses exceed total cash** · Must fix

Full explanation of the new one:

> Expenses, deposits and Mr. Boyle come to $417,000.00, but only $80,000.00 was
> available (opening $20,000.00 plus cash sales $60,000.00).

And under the Closing Balance box, the program refuses to show a negative
balance and says what it actually means instead:

> There's a deficit of $337,000.00 between the total cash available ($80,000.00)
> and total paid out ($417,000.00).

Correct Deposits to `40000`. That line goes; the blank balance is still there,
waiting. The line under the Closing Balance box now reads:

> The figures predict $23,000.00. Input the actual amount of money left.

Point at that sentence. The program will tell you what it expects. It will
never type it in for you. The whole value of the count is that somebody looked
in the drawer.

### Step 6: the drawer is counted, and the program guesses why

Somebody counts the drawer. There is $63,000 in it. Type `63000` in Closing
Balance.

Three lines in the Checks panel:

> **Day doesn't balance** · Needs a reason · Closing Balance
> **First day on record** · Good to know · Opening Balance
> **Matches one of your figures** · Tip · Deposits

Under the Closing Balance box:

> Predicted $23,000.00, counted $63,000.00 — $40,000.00 more than the figures
> account for.

A reason box has opened in card 3, End of day, beside the figure it is about:

> **Day doesn't balance.** Say briefly why before saving.

**Save is greyed out** while that box is empty. A difference cannot be clicked
away.

Now read the tip:

> The difference is exactly "Deposits" ($40,000.00). That figure may have been
> entered twice, or missed out somewhere.

**The real life mistake:** the $40,000 deposit envelope was made up and written
down, but it never left the building. It was still in the drawer when the drawer
was counted. So the drawer holds exactly $40,000 more than the books say, and the
tip names the figure.

### Step 7: the fix

Clear the Deposits box (the money goes to the bank tomorrow).

Everything settles. The reason box disappears and forgets what was typed in it.
The tip goes. One line is left:

> **First day on record** · Good to know · Opening Balance

Under the Closing Balance box:

> Predicted $63,000.00 and that is what was counted. The day balances.

The dock totals read Takings $75,000.00, Expenses $17,000.00, Banked $0.00.

### Step 8: save

Press **Save**. Nothing is said at the top of the page: the Checks panel is
where the program says it. The form stays on the day. The figures stay in the
boxes. Nothing has moved.

The Checks panel changes, because the save has just changed what the books hold.
The first day line has gone, and one new line has taken its place:

> **Day saved, ledger generated** · Good to know

That one line tells the audience two things at once: the day is in the books, and
its ledger has been made. Full explanation (with Day 1's date in place of the
example):

> A ledger has already been generated for 10 September 2026. Before importing into
> QuickBooks, confirm that no journal already exists for this date. If there is a
> QB journal already, delete that journal before importing a new one with updated
> numbers and/or accounts. If the numbers match, there is no need to change the QB
> records.

Under the list of checks there is also a small grey note:

> Saving again will regenerate the ledgers with the current figures and accounts.

That is the one thing the program cannot do for anybody. It cannot see inside
QuickBooks, which is why the explanation asks a person to look. There is no box to
tick: saving a day always regenerates its ledger. Day 6 uses this.

The first day tick box has also gone, and **Save stays available without it**.
That question is asked once. It was answered when the day went in, the audit log
has the answer, and correcting Day 1 later is an ordinary save. The line under
the Opening Balance box still says this would be the first day on record, because
it still is.

### Step 9: Next day

Press **Next day**. The form moves to Day 2, blank, with the cursor already in
the Opening Balance box.

The form did not work out that date for itself. It asked, and the server named
it. *(Front-end behaviour, read from app.js: the page has no "day after" sum at
all any more.)*

*For the maintainer: L1-D, L1-C, L1-B, L2-A, L4-2, L3-D, L3-B.*

---

## Day 2: an ordinary day, and what Next day is for

| Box | Type |
|---|---|
| Opening Balance | 63000 |
| Cash Sales | 45000 |
| POS Deposits to Republic Bank | 12000 |
| Doctor's Fees | 8000 |
| Medical Supplies | 3000 |
| Miscellaneous Items | 1000 |
| Deposits | 30000 |
| Closing Balance | 66000 |

### Step 1: Next day, before anything is saved

Before typing anything, press **Next day**.

Under the buttons, where the person pressing them is looking:

> 11 September 2026 has not been saved yet. Save it before moving on.

Nothing moved and nothing was written. Show the audience that this message is
under the button and **not** in the banner at the top of the page. When somebody
is at the bottom of a long form, a message at the top is a message nobody reads.

Say plainly what the two buttons are: **Save writes the day. Next day only
moves.** Next day never saves anything for anybody.

### Step 2: type the day

Under the Opening Balance box, before anything is typed:

> 10 September 2026 closed with $63,000.00. Count the drawer and enter what is
> there — do not copy this figure.

Type the eight figures straight down the form. The drawer was counted at
$66,000 and the figures agree.

The Checks panel: **Nothing to fix so far**. Under the Closing Balance box:

> Predicted $66,000.00 and that is what was counted. The day balances.

No warnings, no reason, no tick boxes. This is what most days look like, and it
is worth letting the audience sit with that for a moment. One press of Save, one
press of Next day.

### Step 3: save and move on

**Save**. Nothing at the top of the page; the Checks panel now shows **Day saved,
ledger generated**.

**Next day**. The form moves to Day 3.

*For the maintainer: no findings at all until the save, then L3-B.*

---

## Day 3: the clinic was shut

Nothing is typed on this day. Not one figure.

### Step 1: the switch

In card 1, press the **Off day** side of the Work day / Off day switch.

The whole middle of the form disappears: Today's numbers, End of day, the
opening balance, both reason boxes. What is left is the date, the switch, and a
line under the date:

> No ledger will be generated. The next working day carries this balance through.

The Checks panel has one line:

> **Marked as closed** · Good to know

Full explanation:

> 12 September 2026 is recorded as closed. No ledger will be generated for it,
> and the next working day will open with $66,000.00, carried straight through.

Two things to point out. First, the figure in that sentence is Day 2's closing
count, so the audience can see the chain being carried. Second, the boxes were
taken away rather than left empty, because nobody counted a drawer on a day the
clinic was shut and a typed figure would be fiction.

### Step 2: save

Press **Save**. A plain confirmation box comes up first:

> Mark 12 September 2026 as CLOSED?
>
> No ledger will be generated for it, and the next working day will open with the
> balance carried straight through.
>
> If the clinic actually traded, this would erase the day's takings.

Press OK. The day is saved, and the Checks panel says so. The **Marked as
closed** line stays, and under the list a small grey note appears:

> This day has been saved.

(An Off day has no figures on screen, so the note leaves out the Work day's
second sentence, "Saving again will rewrite it with the current figures."
(2026-10-07))

Nothing is added under the buttons. *(Since 2026-10-07. Before, an Off day had
no grey note and the form said "12 September 2026 saved to the books." under the
buttons instead. On a window too narrow to show the Checks panel it still
does.)*

**No daily ledger file is written for it**, and none should be: there was
nothing to post. (So there is no "Day saved, ledger generated" line for this
day, and no note about regenerating ledgers.)

### Step 3: Next day

**Next day** moves to Day 4. The switch resets itself to Work day.

*For the maintainer: L3-C. An Off day sends only the date and its status; the
server carries the balance through itself.*

---

## Day 4: two differences, two reasons

This is the day that shows that each difference is answered on its own.

| Box | Type |
|---|---|
| Opening Balance | 68000 |
| Cash Sales | 30000 |
| POS Deposits To Unspecified Bank | 6000 |
| Doctor's Fees | 7000 |
| Medical Supplies | 1000 |
| Taxi Fare | 3000 |
| Deposits | 18000 |
| Closing Balance | 64000 |

### Step 1: the morning count is wrong

Under the Opening Balance box:

> 12 September 2026 closed with $66,000.00. Count the drawer and enter what is
> there — do not copy this figure.

That is the Off day, passing Day 2's balance along. The chain never broke.

The drawer is counted this morning and there is $68,000 in it, not $66,000. Type
`68000` and leave the box.

Straight away, without waiting for the rest of the day:

> **Opening doesn't match last close** · Needs a reason · Opening Balance

And a reason box opens in card 1, Start of day, beside the opening figure:

> **Opening doesn't match last close.** Say briefly why before saving.

Full explanation:

> The opening balance does not match the last working day. It is $2,000.00 more
> than the $66,000.00 that day closed with. The day's own arithmetic still uses
> the figure that was counted this morning.

That last sentence matters. The program does not quietly rewrite the day around
the figure it expected. It uses what was counted and records the gap.

### Step 2: the day does not balance either

Type the rest of the day. The drawer is counted at close and there is $64,000.
Type `64000` and leave the box.

Two lines now:

> **Day doesn't balance** · Needs a reason · Closing Balance
> **Opening doesn't match last close** · Needs a reason · Opening Balance

And **two reason boxes on screen at once**, each in the card of the figure it is
about: one under the opening balance, one under the closing balance. Each names
its own difference in bold.

Under the Closing Balance box:

> Predicted $69,000.00, counted $64,000.00 — $5,000.00 less than the figures
> account for.

### Step 3: one reason does not cover the other

Type the End of day reason only. For example:

> Counted 64,000 at close; 5,000 short and not found. Reported to the manager.

**Save is still greyed out.** Wait a beat and let the audience notice.

Now type the Start of day reason. For example:

> Drawer counted 68,000 this morning, 2,000 more than last night's count.

**Save turns green.**

These are two different events, hours apart, with two different explanations, and
neither one stands in for the other. A week later "no idea" and "the float was
left in overnight" lead to completely different conversations, and nobody
reconstructs that from memory.

### Step 4: save

**Save**, then **Next day** to Day 5.

Both sentences are now in the books, in their own columns. The audience can see
them at the end of the demo.

*For the maintainer: L2-A and L2-B together, no hint. The server refuses a save
with neither reason with "The opening balance doesn't match the last close and
this day doesn't balance. Add a short reason for each before saving it.", and
with one of the two with the matching single sentence. From the form you never
see those, because the button greys out first.*

---

## Day 6: entered next, while Day 5 is still missing

The form is now sitting on Day 5, blank. **Leave Day 5 empty.** Change the date
selects to Day 6, the day of the demo.

Somebody forgot to enter yesterday. This is what the program does about it.

| Box | Type |
|---|---|
| Opening Balance | 72000 |
| Cash Sales | 21000 → corrected to 12000 |
| POS Deposits To Scotiabank | 4000 |
| POS Deposits to Republic Bank | 3000 |
| Medical Supplies | 6000 |
| Miscellaneous Items | 2000 |
| Deposits | 25000 |
| Closing Balance | 51000 |

### Step 1: the day before is missing

Under the Opening Balance box, before anything is typed:

> The day before this one has not been entered. This day will be saved, but its
> ledger will wait.

Notice what it does not say. It does not object, it does not refuse, and it does
not ask anybody to explain a gap. The program has no calendar and no opinion
about which days should exist.

Notice too that there is **no** reason box for the opening balance on this day.
With no day before it, there is nothing to compare this morning's count against,
so nothing to explain.

### Step 2: type the day, with a swap in the takings

Type the figures. Type Cash Sales as `21000`. The till roll actually says
`12000`: two digits went in the wrong order.

The drawer is counted at close and there is $51,000. Type `51000` in Closing
Balance and **press Save at once**, without leaving the box.

**Save is greyed out, and the press is still answered.** The button has been
grey since the Closing Balance box was blank, and the figure just typed does
not make the day balance, so it stays grey. The press sends nothing; what it
does is say why. The banner:

> Add a short reason before saving this day.

The cursor jumps into the reason box, which has just opened in End of day, with
the line in the Checks panel. *(Since 2026-10-06 the button is grey whenever
the server's check says the day cannot be saved as it stands, even while the
Checks panel is still holding the row back; a press on the grey button shows
what the press used to show, and never sends. A press that lands in the
half-second before the check has answered waits for it and then decides, so
typing the closing balance and pressing Ctrl+S at once still saves a day that
balances.)*

Three lines in the Checks panel:

> **Day doesn't balance** · Needs a reason · Closing Balance
> **Ledger waiting on the day before** · Good to know
> **Digits may be swapped** · Tip

Under the Closing Balance box:

> Predicted $60,000.00, counted $51,000.00 — $9,000.00 less than the figures
> account for.

The tip:

> $9,000.00 divides evenly by 9, which usually means two digits are swapped or a
> decimal point is in the wrong place.

**The real life mistake:** the cashier typed 21,000 where the till roll says
12,000. This is the oldest tell in bookkeeping. Swap any two digits of a figure
and the difference is always a multiple of 9. The program cannot say which
figure, only that the shape of the error is a misplaced digit, and that is
usually enough for somebody to find it in thirty seconds.

And the notice, which is the point of this day:

> The day before this one has not been entered yet, so this day's ledger cannot
> be finished. The day itself is saved. The ledger will be produced
> automatically once the missing day is entered.

### Step 3: fix it and save

Check the till roll. Correct Cash Sales to `12000`.

The day balances. The reason box disappears. The tip goes. One line is left:

> **Ledger waiting on the day before** · Good to know

Under the Closing Balance box:

> Predicted $51,000.00 and that is what was counted. The day balances.

Press **Save**. It saves. Nothing is said under the buttons; the Checks panel
says it instead, with a small grey note under the list of checks:

> This day has been saved. Saving again will rewrite it with the current figures.

**Its ledger file is not written**, because the overnight comparison belongs in this day's ledger and
there is nothing yet to compare against. Exactly one day is affected: every
other day in the month posts normally.

Do **not** press Next day. Stay here.

> **Note for the presenter.** The report this save writes ends with
> `month check : ** OFF BY $8,000.00 **` and an explanation that a day is
> probably missing. That is the month level version of the same check doing its
> job, and it clears itself as soon as Day 5 is entered. If you plan to open the
> report during the demo, open it after Day 5, not now.

*For the maintainer: L3-A, L2-A, L4-1.*

---

## Day 5: the missing day, and the held ledger being released

Change the date selects back to Day 5. Day 5 is not in the books, so it comes up
blank, just as **Clear** leaves it: Day 6's figures do not follow you. *(Since
2026-10-07 a date that is in the books comes up with its saved figures instead.
"Day 6 again" shows that.)*

| Box | Type |
|---|---|
| Opening Balance | 64000 |
| Cash Sales | 40000 |
| POS Deposits To Scotiabank | 8000 |
| Doctor's Fees | 1000 → corrected to 10000 |
| Medical Supplies | 2000 |
| Deposits | 20000 |
| Closing Balance | 72000 |

### Step 1: a decimal point in the wrong place

Type the day. Type Doctor's Fees as `1000`. The receipt says `10,000`: a zero
was dropped.

The drawer was counted at $72,000. Type `72000` in Closing Balance and leave the
box.

Four lines:

> **Day doesn't balance** · Needs a reason · Closing Balance
> **Day after already on record** · Good to know · Closing Balance
> **Digits may be swapped** · Tip
> **Decimal point may be off** · Tip · Doctor's Fees

The second line is the one that belongs to this day alone. Day 6 is already in
the books, waiting on this one, and saving this day is what releases it. The
Closing Balance box is outlined in the notice colour. Full explanation:

> 15 September 2026 is already on record and was waiting on this day. Check that
> its opening balance matches this closing balance. If they do not agree, that day
> will need an opening reason before its ledger can be made.

(with Day 6's date in place of the example). Say why it is there: the closing
count being typed here is the figure Day 6's morning is about to be compared
against, for the first time, and the person holding the count sheet is the only
one who can notice that the two do not agree. Nothing is wrong and nothing is
being asked for. It is a reminder, not a difference.

Under the Closing Balance box:

> Predicted $81,000.00, counted $72,000.00 — $9,000.00 less than the figures
> account for.

The second tip names the box:

> The difference is exactly nine times "Doctor's Fees" ($1,000.00). That figure
> probably has its decimal point in the wrong place.

**The real life mistake:** $10,000 was paid to the doctor and $1,000 was typed.
The difference is nine times the figure that was typed, which is what a lost zero
always looks like.

These two tips always travel together, and it is worth saying so: a difference
that is nine times a figure is automatically a multiple of nine, so the first tip
can never be absent when the second one fires. The second one is the useful one,
because it names the box.

### Step 2: fix it, and watch the ledger catch up

Correct Doctor's Fees to `10000`.

The day balances. The difference and both tips clear. One line is left, the
reminder about Day 6:

> **Day after already on record** · Good to know · Closing Balance

> Predicted $72,000.00 and that is what was counted. The day balances.

Day 6's opening count was $72,000 and this closing count is $72,000, so the two
mornings do agree and there is nothing to do. Press **Save**.

Nothing visible happens beyond the usual confirmation, and that is the part to
narrate. Behind that one press, the program went back to Day 6, found that the
day before it now exists, worked out the overnight comparison it could not work
out before, and wrote Day 6's ledger. The gap closed itself. Nobody had to
remember.

You can prove it at the end of the demo in three places: Day 6 now has a ledger
file, the audit log has a line `RELEASED previously held ledger for` Day 6, and
the report for this save says `LEDGERS WAITING ON A MISSING DAY: None. Every
recorded day has a ledger.`

*For the maintainer: L2-A, L3-E, L4-1 and L4-3 before the fix; L3-E alone after
it, and it goes once this day has a row of its own. The save answers with Day 6
in its `released` list.*

---

## Day 6 again: a saved day brought back, corrected, its ledger regenerated, and the end of the road

Change the date selects to Day 6. Day 5's figures go, and because Day 6 is in the
books it comes up as it was saved: the boxes fill with its figures straight away.
The cursor stays in the date select and the page does not move. Nothing appears
at the top of the page and there is no editing mode: it is an ordinary form with
the figures back in it. The form has no "edit" step; a day is corrected by
changing a figure and saving again, which replaces the day in the books.
*(Since 2026-10-07, when the owner asked for saved days to load with their saved
figures. Before, the form came up blank and the day was brought back with a
"Show saved figures" link.)*

| Box | Now holds |
|---|---|
| Opening Balance | 72000 |
| Cash Sales | 12000 |
| POS Deposits To Scotiabank | 4000 |
| POS Deposits to Republic Bank | 3000 |
| Medical Supplies | 6000 |
| Miscellaneous Items | 2000 |
| Deposits | 25000 |
| Closing Balance | 51000 |

The Checks panel shows only what is true of Day 6, which is in the books with its
ledger now made:

> **Day saved, ledger generated** · Good to know

with the grey note under it (Saving again will regenerate the ledgers with the
current figures and accounts.). The day balances and there is nothing else to say.

### Optional: Clear, and the way back (2026-10-07)

Press **Clear** (or **Ctrl+Alt+C**). The date stays on Day 6 and every box
empties. Because Day 6 is in the books, a quiet link appears under the grey note,
in the same style as "See full explanation":

> Show saved figures

It shows only after Clear on a saved day. It is not a check and is not counted
with them. Press it, or **Ctrl+Alt+Z**. Day 6 comes back exactly as it was saved,
the page scrolls to the top with the cursor in the Opening Balance box, and the
link goes. Typing in the cleared form does not hide the link (pressing it then
replaces what was typed); picking another date, a save, and Next day when it
moves on do. (Next day refuses to leave the cleared form, because the blank
boxes are not what the books hold, and the link stays.) If you show this, bring
Day 6 back before going on to Step 1.

If the day cannot be brought back, one plain sentence appears right under the
link instead (for example "15 September 2026 is not in the books."). If the
server cannot be reached when a date is picked, the form stays blank and the
Checks panel says so in one sentence, for example "Could not look up 15
September 2026. LDGR has stopped. Unsaved figures will need to be re-entered.
Close this window and open LDGR again." (the wording since 6.0). Either sentence goes away on the next date change, on Clear, on a
successful load or on a successful save.

### Step 1: the closing count was read off the wrong line

The count sheet is found the next morning. The drawer held $44,000, not $51,000.
Change Closing Balance to `44000`.

The warnings come up at once this time, without waiting for the box to be left,
because a day brought back from the books already has its counts in it.
*(Front-end behaviour, read from app.js: both balance keys are marked as visited
when a saved day is loaded.)*

Three lines:

> **Day doesn't balance** · Needs a reason · Closing Balance
> **Day saved, ledger generated** · Good to know
> **Card and cash may be mixed up** · Tip

Under the Closing Balance box:

> Predicted $51,000.00, counted $44,000.00 — $7,000.00 less than the figures
> account for.

The tip:

> The difference is exactly the total of the card takings ($7,000.00). Card money
> may have been entered as cash, or the other way round.

**The real life mistake:** somebody paid by card and the sale was rung through as
cash as well. The card money never went into the drawer; it goes straight to the
bank. So the drawer is short by exactly the card total, and that is the one and
only way this program can say anything at all about a card figure. Note that the
$7,000 here is two card boxes added together, $4,000 and $3,000, which is why the
tip talks about the total rather than naming a box.

### Step 2: Next day refuses again, for the other reason

Press **Next day**.

Under the buttons:

> The figures on screen for 15 September 2026 have not been saved. Save them
> before moving on.

This is the second of the two refusals. The day *is* in the books; what is on the
screen is not what the books hold. The comparison is made by the server against
the journal, because a page opened after a save has nothing of its own to compare
with.

### Step 3: save the correction

Type the reason. For example:

> Count sheet says 44,000. 7,000 short; the card total is exactly 7,000 so a card
> sale may have been rung up as cash. Checking with the bank.

Press **Save** (or **Ctrl+S**). Nothing appears at the top of the page. The
journal row was replaced, and the ledger file was regenerated from the figures now
on screen, so it holds the $44,000 count. The Checks panel still says **Day saved,
ledger generated**, and the grey note under it says why pressing Save was safe to
repeat: saving again regenerates the ledgers with the current figures and
accounts.

Say what the program cannot do here. It cannot see inside QuickBooks. If the Day 6
ledger had already been imported, the full explanation on that line is what
tells staff to look for the journal for that date and delete it before importing
the new one. If the figures had not changed, there would be nothing to change in
QuickBooks.

The regeneration is recorded: the audit log gets `OVERWROTE daily ledger ...
replacement was requested`, and the day is listed in the report under **LEDGERS
REGENERATED FOR A DAY THAT ALREADY HAD ONE**, with a reminder that the program
cannot see inside QuickBooks.

### Step 4: there is nowhere left to go

Press **Next day**.

Under the buttons:

> Today is saved. There is no next day to enter yet.

The form stays where it is. Nobody can enter tomorrow's drawer, because nobody
has counted it.

*For the maintainer: L2-A, L3-B, L4-4. The refusal is `/api/next`
answering 409 with `changed:true` (the earlier `saved:false` one is Day 2); the last press is a 200
with `next: null`.*

---

## What the demo wrote

Seven saves over six days. Open the scratch folder. This is everything, with the
year and month of your dates in place of `2026` and `09`:

```
C:\ldgr-demo\
  audit_log.txt
  Reports\
    Daily Report <the demo date>.txt
  2026\09\
    Daily Journal 09-2026.csv
    Monthly Ledger 09-2026.csv
    Daily Ledgers 09-2026\
      Daily Ledger <Day 1>.csv
      Daily Ledger <Day 2>.csv
      Daily Ledger <Day 4>.csv
      Daily Ledger <Day 5>.csv
      Daily Ledger <Day 6>.csv
```

Six days inside one calendar month make the tidiest demo, because everything then
lands in one journal. If the block straddles a month end it all still works, but
there will be two month folders, each with its own journal and monthly ledger.

Five daily ledgers for six days. **There is no ledger for Day 3**, because Day 3
was an Off day and had nothing to post. Point at the gap; it is the proof.

### The Daily Journal

`Daily Journal 09-2026.csv` is the source of truth. One row per day, always
sorted by date, and a date can never appear twice however many times it is
saved. Open it to look at it. **Never edit a Daily Journal in a spreadsheet**;
the program reads it back.

Its columns, in order: the date, then the ten figures from the form, then the
opening and closing balances, then two columns the program works out for itself
(**day_variance** and **overnight_variance**), then:

| Column | What is in it after this demo |
|---|---|
| **Status** | `trading` for five days, `closed` for Day 3 |
| **Reason** | Day 4's end of day sentence, and Day 6's |
| **Opening Reason** | Day 4's start of day sentence |

Day 4 is the row to show. It has a figure in both variance columns and a
different sentence in each of the two reason columns. That is the whole point of
the design: two differences, two explanations, kept apart.

The headers are the program's own short names for the categories, not the labels
on the form. `POS_Scotia` is the box labelled "POS Deposits To Scotiabank".

### The daily report

`Reports\Daily Report <date>.txt` has one block per save, appended, so the demo
leaves seven blocks in it. The last one is the one to read out. It has:

* the day that was saved and what happened to its journal row and its ledger;
* **DIFFERENCES REQUIRING ATTENTION**, each one marked SURPLUS or SHORTAGE and
  `during trading` or `overnight`, with its own reason printed underneath;
* **LEDGERS WAITING ON A MISSING DAY**, which repeats every day until it is
  empty;
* **LEDGERS REGENERATED FOR A DAY THAT ALREADY HAD ONE**;
* **MONTH TO DATE**, with the over and short totals and a month level check;
* and a closing caution worth reading aloud, that a day which balances has passed
  one test and can still be wrong.

Every figure in it is written the way the form writes money, `$5,000.00`, with a
minus sign in front of a total that is short.

### The audit log

`audit_log.txt` has one indented block per run. The lines this demo produces
include `GENESIS: accepted ... opening balance on trust`, `closed day — no ledger
generated for ...`, `HELD ledger for ... the day before it is not on record`,
`RELEASED previously held ledger for ...`, `REPLACED existing entry ...`,
and `OVERWROTE daily ledger ...
replacement was requested`.

Tips are deliberately never written to the audit log. They are guesses, and a
guess has no business in a record.

---

## Appendix A: the things that never reach the checks

Some bad input is turned away before any check runs. The browser stops it as it
is typed, and the server refuses it again at its own door. There is no warning
to show for these, only a refusal, so there is nothing in the Checks panel to
point at. Try them live; they take seconds each.

| Try this | What the audience sees |
|---|---|
| Type `-500` in any money box | Under the box, in red: **Amounts cannot be negative.** The box goes red, Save greys out, nothing is sent. |
| Type `abc` in any money box | **Numbers only — no letters or symbols.** |
| Type just `.` | **Enter a number.** |
| Type `99999999` | **That looks too large — please check it.** |
| Pick tomorrow's date | Under the date row: **That day has not happened yet.** Both Save and Next day grey out and no check is even requested. |
| Look for 31 September | It is not in the day list. The list is rebuilt for each month. |
| Look for the year 1999 | It is not in the year list. Only the current year and the two before it are offered. |

A minus sign is refused rather than accepted because every box on the form is a
quantity of cash. Money moving the other way is a different kind of transaction
and needs its own box, which is a decision for the owner, not a shortcut through
a minus sign.

*For the maintainer: the checks L1-A (negative), L1-E (bad date) and the
not-a-number half of L1-D exist and are tested, but cannot be reached through the
form or through any endpoint, because `record_from_payload` throws first. Driven
directly, `/api/check` answers 400 with `"Taxi Fare" cannot be negative.`,
`"Taxi Fare" is not a number.` and `2026-09-16 is in the future.`. The
three-decimal half of L1-D is reachable, and Day 1 step 3 shows it.*

---

## Appendix B: every message in the demo, and where it fires

For the maintainer only. **None of these codes are ever shown to the people
entering days**, and they should not be shown to an audience either. They exist
for the audit log, the tests and whoever maintains `Checks.jl`.

| Code | Title on the row | Level | Where in the demo |
|---|---|---|---|
| L1-B | Expenses exceed total cash | Must fix | Day 1 step 5 |
| L1-C | Closing Balance Not Entered | Must fix | Day 1 step 4 |
| L1-D | Not a valid amount | Must fix | Day 1 step 3 |
| L2-A | Day doesn't balance | Needs a reason | Day 1 step 6, Day 4, Day 5, Day 6 twice |
| L2-B | Opening doesn't match last close | Needs a reason | Day 4 |
| L3-A | Ledger waiting on the day before | Good to know | Day 6, first entry |
| L3-B | Day saved, ledger generated | Good to know | after every save of a day that has a ledger |
| L3-C | Marked as closed | Good to know | Day 3 |
| L3-D | First day on record | Good to know | Day 1, until it is saved |
| L3-E | Day after already on record | Good to know | Day 5, the gap filler |
| L4-1 | Digits may be swapped | Tip | Day 6 first entry (alone), Day 5 (with L4-3) |
| L4-2 | Matches one of your figures | Tip | Day 1 step 6 |
| L4-3 | Decimal point may be off | Tip | Day 5 |
| L4-4 | Card and cash may be mixed up | Tip | Day 6 again |

Two things about the tips are designed in and cannot be shown otherwise. **L4-3
can never appear without L4-1**, because a difference that is nine times a figure
is always a multiple of nine. And **L4-4 needs at least two card boxes** to
appear on its own: with a single card figure equal to the difference, L4-2 fires
on that box as well, which is why Day 6 splits $7,000 into $4,000 and $3,000.

A Must fix suppresses the difference checks and every tip, which is why Day 1
shows its Must fixes first and only then gets a difference and a tip. The one
exception is L2-B, which still runs behind a Stop unless the Stop is about the
opening balance or the date. That is what lets the opening balance be questioned
first thing in the morning, while the closing balance is still blank.

---

## If something goes wrong mid demo

| Problem | What to do |
|---|---|
| Save is greyed out and it is not obvious why | Press it: a press on the grey button sends nothing, but it says why (the held-back row and its explanation, the reason box, the first-day box, or the red box). One of five things: the server's last check found a Must fix or a difference with no reason (including one the Checks panel is still holding back: a balance box nobody has visited, or the cursor still in the box with the difference), a reason box on screen is empty, the first day box is unticked, the date is bad, or a money box is red. A blank form is grey on purpose: it is not a saveable day. |
| A warning is on screen for figures that are no longer there | Press **Clear**, which keeps the date, and type the day again. |
| The whole demo needs restarting | Stop the server, empty the scratch folder, start it again. Day 1 becomes the first day on record once more. |
| A saved day's figures are not in the boxes | (2026-10-07) Picking a saved date brings its figures up by itself. If **Clear** was pressed on it, press **Show saved figures** under the grey note in the Checks panel, or **Ctrl+Alt+Z**; the link shows only after Clear on a saved day. If a figure was typed while the date was still being looked up, what was typed is kept: press Clear, then the link. If the Checks panel says "Could not look up …", the server could not be reached: in the packaged app, close LDGR and open it again; run from a terminal, check the terminal window. Then pick the date again. |
| The page says "LDGR has stopped" | The program behind the form stopped. In the packaged app (6.0), close the window and open LDGR again, and read `C:\LDGR\logs\` if it repeats. Run from a terminal, the terminal window was closed: start it again. |
