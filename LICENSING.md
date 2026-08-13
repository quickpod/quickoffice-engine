# Quick Office — licensing verdict and obligations

**Question asked:** may QuickOpen build Quick Document, Quick Spreadsheet and
Quick Presentation *from the LibreOffice codebase* and ship them?

**Verdict: YES — with three obligations, all of them cheap and all of them met
by this repo.** Every one is discharged by a file in this directory. What
follows is the reasoning and the receipts, so nobody has to re-derive it.

---

## 1. What licence the code is actually under

LibreOffice states it plainly: *"LibreOffice is made available subject to the
terms of the Mozilla Public License v2.0."* The source tree we build from
carries the licence texts itself:

| file in `core/` | licence |
|---|---|
| `COPYING.MPL` | Mozilla Public License v2.0 — the primary licence |
| `COPYING.LGPL` | GNU LGPL v3+ — contributions are licensed jointly MPLv2 + LGPLv3+ |
| `COPYING` | GNU GPL v3 — for the components that carry it |
| `readlicense_oo/license/NOTICE` | Apache-2.0 NOTICE for the Apache OpenOffice-derived code, Lucene, redland, BeanShell, OpenSSL |

So the base is **MPL-2.0**, with **Apache-2.0** parts inherited from Apache
OpenOffice and **LGPLv3+** as the joint licence on contributions.

## 2. Why that permits what we are doing

MPL-2.0 is **file-level copyleft**, which is the whole reason this is workable:

- **Combining with our own code is explicitly allowed.** Mozilla's own FAQ:
  *"May I combine MPL-licensed code and BSD-licensed code in the same
  executable program? What about Apache? Yes to both."* Our Apache-2.0 launcher
  and theming code can sit in the same product as MPL-2.0 engine code.
- **A "Larger Work" may be distributed under our own terms**, provided the
  MPL-covered files keep their MPL terms and their source stays available
  (MPL-2.0 §3.3).
- **Modifying and redistributing is the licence's core grant.** Modified MPL
  files stay MPL and their source must be published (§3.1, §3.2).
- **Renaming the product is not restricted by the licence.** The licence
  restricts the *licence's* name and the *notices*, not the product's name.

The obligations that fall out of that are §3.2 (source availability), §3.4
(don't strip notices) and the Apache-2.0 §4(d) NOTICE requirement.

## 3. Why the NAME has to change — trademark, not copyright

"LibreOffice" and its logos are trademarks of **The Document Foundation**, and
the licence grants no trademark rights (MPL-2.0 §2.3 is explicit that it grants
no trademark licence). TDF's trademark policy requires that software which is
*not substantially unmodified* be described as **"a derivative of"** or
**"based on"** LibreOffice, and that a product name *"clearly and unambiguously
distinguishes the product from LibreOffice"* without implying *"any official
association or identity with TDF."*

This is the same route MariaDB took from MySQL, and the one LibreOffice itself
took from OpenOffice. It is also exactly what we want anyway: our products are
**Quick Document**, **Quick Spreadsheet** and **Quick Presentation**, under the
QuickOpen brand — distinct names, our own icons, our own splash, our own About
box. No TDF logo, no TDF name in the product identity, no claim of endorsement.

Note this lands on the right side of AIQuick product requirement #11
(trademark-free inspiration only, no third-party assets) for the same reason.

## 4. The three obligations, and where each is discharged

| # | Obligation | Source | Discharged by |
|---|---|---|---|
| 1 | **Attribution + licence notices.** Ship the MPL/LGPL/GPL texts and the Apache NOTICE; state that the product is based on LibreOffice; keep in-source licence headers intact. | MPL-2.0 §3.4, Apache-2.0 §4(d), TDF trademark policy | [`NOTICE`](NOTICE), shipped in every installer and shown in Help ▸ About |
| 2 | **Source availability.** Anyone who receives a binary must be told how to get the source of the MPL-covered files, including our modifications. | MPL-2.0 §3.2 | Public repo + the "Source code" link in About; every release ships its exact source tag |
| 3 | **Distinct branding.** No TDF marks in the product identity; describe as *based on* LibreOffice. | TDF trademark policy | Our own name/icons/splash; the "based on" wording is in `NOTICE` and About |

**No permission from TDF is needed** for any of this, and none was sought —
these are the standing public terms. What *would* need permission is using the
LibreOffice name or logo as our product identity, which we deliberately do not.

## 5. What this means for our own licence

- Files we **modify** in `core/` stay **MPL-2.0** (file-level copyleft) and
  their source is published.
- Files we **author** — launchers, the Aura theme, branding assets, packaging —
  are **Apache-2.0**, like the rest of the QuickOpen fleet. MPL-2.0 §3.3 allows
  exactly this combination.
- The shipped product is therefore a Larger Work: MPL-2.0 engine + Apache-2.0
  QuickOpen layer, with both licences shipped and both sources public.

## 6. What we must NOT do

- Call the product LibreOffice, or use the LibreOffice/TDF logo or name as
  product identity.
- Imply TDF endorsement, partnership, or that this *is* LibreOffice.
- Strip or alter licence headers inside the source files.
- Ship binaries without telling recipients where the source is.

---

*Sources: LibreOffice licence page (documentfoundation.org), the `COPYING*` and
`readlicense_oo/license/NOTICE` files in the source tree, the MPL-2.0 FAQ
(mozilla.org/MPL/2.0/FAQ), and TDF's trademark policy
(wiki.documentfoundation.org/TDF/Policies/Trademark_Policy).*
