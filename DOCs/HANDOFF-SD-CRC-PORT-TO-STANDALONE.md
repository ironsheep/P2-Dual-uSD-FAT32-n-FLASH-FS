# HANDOFF -- Port SD command-CRC hardening to the standalone microSD driver

**To:** the agent maintaining the **standalone microSD FAT32 driver** (separate repo).
**From:** the dual SD+Flash filesystem driver project (P2 Edge).
**Date:** 2026-07-05
**Origin change:** dual driver v1.3.1 / SD sub-driver v1.5.1, commit `ea93f0d`
("Harden shared SD/Flash bus against MBR corruption via CMD59 CRC-ON").

This document is **self-contained** -- it embeds the exact code so you can apply it without
access to the dual-driver repo. All code is Spin2/PASM2 for the Parallax Propeller 2.

---

## 0. TL;DR

The dual driver now (a) sends a **real CRC-7 on every SD command** instead of a dummy `$FF`,
and (b) turns on **card-side CRC checking** (`CMD59`) for the whole SPI session. On the dual
driver this is an **anti-brick** measure for a bus the microSD *shares with onboard Flash*.

**Your driver is SD-only, so that specific motivation does not apply to you.** For you the value
is plain **data integrity** (catch bus noise / marginal wiring), which is worth having but
optional. Port table and a **card-compatibility caveat with a recommended fallback** are below --
read section 2 before enabling `CMD59`.

---

## 1. Why the dual driver did this (context, not necessarily your reason)

On the P2 Edge the microSD and the onboard boot-Flash **share four SPI pins with swapped roles**
(P60 = SD-CS / Flash-SCK, P61 = SD-SCK / Flash-CS, P59/P58 shared MOSI/MISO). Every Flash access
physically drives the SD card's CS/SCK/data. Occasionally that stray traffic can be latched by the
card as a *destructive* command (a write to LBA 0, an erase, or `CMD42` LOCK), which wipes the MBR
or locks the card -- damage a re-init cannot undo. Field reports showed exactly this.

With CRC checking on, the card **rejects** any command frame whose CRC-7 doesn't match, so stray
frames are thrown out instead of executed. **A standalone SD-only driver has no shared bus, so this
attack surface doesn't exist for you.** Enabling CRC on your side only buys you rejection of
genuinely corrupt command frames (electrical noise, bad connectors, long leads).

---

## 2. CARD-COMPATIBILITY CAVEAT -- read before enabling CMD59

Your concern about older cards is the right one. Two separate facts:

1. **Sending a correct CRC-7 on every command is universally safe.** A *valid* CRC is always
   acceptable to any SD card, whether checking is on or off: with checking off the card ignores
   the CRC byte; with checking on it validates it. So change **#A below (per-command real CRC)
   carries no compatibility risk** and can be adopted unconditionally.

2. **Enabling checking (`CMD59`) is spec-safe but the dual driver has NO fallback.** Per the SD
   Physical Layer spec, CRC generation/checking is *mandatory* for compliant SD/SDHC/SDXC cards;
   SPI mode merely defaults it off (except CMD0/CMD8 during init). So compliant cards are fine.
   **But the dual driver does not verify CMD59 was accepted and has no COM_CRC_ERROR handling or
   back-off anywhere.** If a marginal/old/off-brand card mishandled CRC after CMD59-ON, its
   commands would start being rejected (R1 bit3 = COM_CRC_ERROR, `$08`) and I/O would fail with
   no automatic recovery -- it would look like a dead card.

   > Honesty note from the origin project: this was verified against the SD **spec** and one
   > modern test card (full regression, zero CRC errors). It was **not** tested across a range of
   > old cards. The dual driver accepts this because it targets known Edge hardware + modern cards.

**RECOMMENDATION for your broad-card-range standalone driver:** if you adopt `CMD59`, add the
graceful fallback the dual driver lacks:

```
' After enabling CRC checking, probe with one command that carries a correct CRC.
' If the card reports COM_CRC_ERROR ($08) despite a valid CRC, its CRC engine is
' unreliable -- disable checking and fall back to dummy CRCs so the card still works.
resp := cmd(59, 1)                          ' CRC_ON_OFF, arg 1 = ON
r1 := <probe, e.g. CMD13 / send status, with a real CRC-7>
if r1 & $08                                 ' COM_CRC_ERROR
  cmd(59, 0)                                ' CRC_ON_OFF, arg 0 = OFF -- revert
  crc_checking_active := false
else
  crc_checking_active := true
```

With this, cards that support CRC get the integrity benefit and cards that don't are commanded
normally. (For an SD-only driver there is no anti-brick downside to falling back, because there is
no shared bus to protect against.)

---

## 3. The changes, precisely (apply what fits an SD-only driver)

Applicability to a **standalone SD-only** driver:

| # | Change | Adopt? | Note |
|---|--------|--------|------|
| A | `cmd_crc7()` helper + real CRC-7 on **every** command | **Yes** | No compat risk. The safe, high-value core. |
| B | `CMD59` CRC-ON at init | **Optional** | Integrity only (no shared bus). Add the section-2 fallback if you do. |
| C | `CMD59` re-arm after any re-init that issues `CMD0` | **Only if applicable** | `CMD0` resets checking to off. If you have no re-init path, skip. |
| D | Park idle SPI lines high during bus hand-off | **N/A** | Shared-bus specific; you have no Flash to switch to. |
| E | Replace bare `WAITATN()` with a done-flag poll | **Evaluate** | Only if you use a worker-cog + ATN design exposed to spurious ATN. Unrelated to CRC. |

### Change A -- `cmd_crc7()` and per-command CRC  (RECOMMENDED)

Add this helper. It computes the CRC-7 of the 6-byte command frame and returns the final frame
byte `((crc << 1) | stop-bit)`. **Spec test vectors: `cmd_crc7(0, $0) -> $95`,
`cmd_crc7(8, $1AA) -> $87`** -- assert these before trusting it.

```
PRI cmd_crc7(op, parm) : frame | fb[2], i, d, crc
' CRC-7 of a 6-byte SD command frame, returned as the final frame byte ((crc << 1) | stop bit).
' A correct CRC is accepted whether or not card-side checking is on, so this is always safe.
' Spec vectors: CMD0/0 -> $95, CMD8/$1AA -> $87.
'
' @param op - Command number (0-63)
' @param parm - 32-bit command argument
' @returns frame - CRC byte to send after the 4 argument bytes

  BYTE[@fb][0] := $40 | op
  BYTE[@fb][1] := parm >> 24
  BYTE[@fb][2] := parm >> 16
  BYTE[@fb][3] := parm >> 8
  BYTE[@fb][4] := parm
  crc := 0
  repeat i from 0 to 4
    d := BYTE[@fb][i] & $FF
    repeat 8
      crc := (crc << 1) & $FF
      if (d ^ crc) & $80
        crc ^= $09
      d := (d << 1) & $FF
  frame := ((crc << 1) | 1) & $FF
```

Then, **at every place your driver transmits a command frame**, replace the hard-coded CRC byte
with `cmd_crc7(op, arg)`. In the dual driver these sites were, for reference:

- The main `cmd(op, parm)` sender -- old code sent a static `$95` for CMD0 and `$87` otherwise;
  now sends `sp_transfer(cmd_crc7(op, parm), 8)` for all commands. Example:
  ```
  sp_transfer($40 | op, 8)
  sp_transfer(parm, 32)
  sp_transfer(cmd_crc7(op, parm), 8)      ' real CRC7 on every command
  ```
- Any dedicated `CMD13` / send-status path that sent `$FF` -> `cmd_crc7(13, 0)`.
- Any generic "read a card register" path (CSD/CID/SCR/SD-status/CMD6) that took a fixed
  `crc_byte` argument -> compute `cmd_crc7(cmd_num, arg)` instead.
- `CMD12` (STOP_TRANSMISSION) already uses the correct static `$61` -- leave it.

> **Audit rule:** once card-side checking is ON, *every* command must carry a valid CRC or the
> card rejects it. Grep your source for every byte sent immediately after a 32-bit command
> argument and confirm none still send a dummy `$FF`/static value (except CMD12's `$61`). A missed
> site shows up as COM_CRC_ERROR (`$08`) in R1 on hardware.

### Change B -- `CMD59` CRC-ON at init  (OPTIONAL; add section-2 fallback)

After the card is out of idle / basic init is done (dual driver does it right before its ACMD41
op-cond loop), issue:

```
resp := cmd(59, 1)                         ' CMD59 CRC_ON_OFF, arg bit0 = 1 = ON
```

`CMD59` arg is a bitfield; bit 0 = 1 enables checking, 0 disables. **Only enable this together
with change A (real CRCs everywhere) -- otherwise your own next command is rejected.** For a
broad-card-range driver, wrap it with the fallback in section 2.

### Change C -- re-arm `CMD59` after `CMD0`

`CMD0` (GO_IDLE) resets CRC checking back to OFF. If your driver ever re-issues `CMD0` after the
initial init (a recovery / re-init path), re-issue `cmd(59, 1)` there too. If you have no such
path, skip.

### Change D -- park idle lines high  (NOT APPLICABLE)

Shared-bus only: the dual driver drives its shared SD/Flash lines high (`pinh`) instead of leaving
them floating during a device hand-off, so noise can't clock bits into the card. A single-device
SD driver has nothing to hand off to -- ignore.

### Change E -- `WAITATN()` -> done-flag poll  (EVALUATE; unrelated to CRC)

Unrelated robustness fix, included only for completeness. If your driver uses a worker cog that a
caller waits on via `WAITATN()`, a spurious/concurrent ATN (e.g. from an actor message fabric)
can wake the caller early so it reads the previous op's result. The dual driver replaced the bare
wait with a poll of the worker's done-flag:

```
' worker clears pb_cmd to CMD_NONE, then COGATNs the caller
repeat
  if pb_cmd == CMD_NONE
    quit
  WAITATN()
```

Adopt only if your architecture has the same exposure.

---

## 4. How to verify (on hardware)

1. **Unit-check the CRC first:** assert `cmd_crc7(0,$0) == $95` and `cmd_crc7(8,$1AA) == $87`.
   If either is wrong, stop -- the algorithm is misapplied.
2. **Run your full regression** with change A alone first (real CRCs, checking still off). This
   should be a no-op behaviorally -- a correct CRC is ignored when checking is off. Confirm zero
   regressions.
3. **Then enable change B** and re-run. Watch every log for **R1 bit3 = COM_CRC_ERROR (`$08`)**.
   Zero occurrences = every command path sends a correct CRC. Any occurrence points straight at a
   command-send site still using a dummy/static CRC (see the audit rule in change A).
4. **Old-card pass:** if you care about legacy cards, test the section-2 fallback by (if possible)
   forcing a COM_CRC_ERROR and confirming the driver reverts to CRC-OFF and keeps working.

The origin project's verification, for reference: full regression 1,357 tests / 0 failures with
**zero COM_CRC_ERROR**, plus a sentinel stress harness (SD-only + interleaved load) 7/7 with no
sector corruption and no card lock.

---

## 5. Open items / notes

- The dual driver deliberately shipped **without** the section-2 fallback (Edge + modern-card
  assumption). Whether to also retrofit that fallback into the dual driver is an open question on
  the origin side; for your broad-card-range standalone driver it is **recommended**.
- `CMD59` protection persists across a P2 reset (card keeps power) until the next full init/`CMD0`.
  Not relevant to correctness, but useful to know when reasoning about card state.
- Nothing here changes data-block CRC-16 on read/write payloads -- that is a separate mechanism
  and both drivers already compute it correctly.
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
