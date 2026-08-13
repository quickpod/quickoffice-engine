#!/usr/bin/env python3
r"""Generate the sample documents the Quick Office screenshots open.

Flat ODF (.fodt/.fods/.fodp) on purpose: one plain XML file per document, no
zip container, so these are readable in a diff and editable without a build
step — and LibreOffice opens them natively, so no conversion pass is needed
before a screenshot.

The content is deliberately ordinary business material with invented names, so
a published screenshot can never leak anything real (same rule the fleet's
other capture tool follows: RFC 5737 addresses, RFC 2606 domains, invented
people).

    make-samples.py [outdir]
"""

import os
import sys

FODT = """<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
 office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.text">
 <office:styles>
  <style:style style:name="Title" style:family="paragraph"
   style:next-style-name="Standard">
   <style:paragraph-properties fo:text-align="center" fo:margin-bottom="0.35cm"/>
   <style:text-properties fo:font-size="26pt" fo:font-weight="bold"/>
  </style:style>
  <style:style style:name="Heading_20_1" style:display-name="Heading 1"
   style:family="paragraph" style:next-style-name="Standard">
   <style:paragraph-properties fo:margin-top="0.5cm" fo:margin-bottom="0.2cm"
    fo:keep-with-next-paragraph="always"/>
   <style:text-properties fo:font-size="17pt" fo:font-weight="bold"
    fo:color="#1a2130"/>
  </style:style>
  <style:style style:name="Heading_20_2" style:display-name="Heading 2"
   style:family="paragraph" style:next-style-name="Standard">
   <style:paragraph-properties fo:margin-top="0.35cm" fo:margin-bottom="0.15cm"
    fo:keep-with-next-paragraph="always"/>
   <style:text-properties fo:font-size="13pt" fo:font-weight="bold"
    fo:color="#3a5fd0"/>
  </style:style>
 </office:styles>
 <office:automatic-styles>
  <style:style style:name="Quote" style:family="paragraph"
   style:parent-style-name="Standard">
   <style:paragraph-properties fo:margin-left="1cm" fo:margin-right="1cm"
    fo:margin-top="0.3cm" fo:margin-bottom="0.3cm" fo:border-left="2pt solid #5b86f7"
    fo:padding-left="0.4cm"/>
  </style:style>
 </office:automatic-styles>
 <office:body><office:text>
  <text:p text:style-name="Title">Northwind Terrace — Structural Survey</text:p>
  <text:p text:style-name="Standard">Prepared for Marlow &amp; Finch LLP · 14 August 2026 · Reference NT-2026-114</text:p>
  <text:h text:style-name="Heading_20_1" text:outline-level="1">1. Summary</text:h>
  <text:p text:style-name="Standard">The property is in sound structural condition. Two matters require attention within twelve months: the parapet flashing on the north elevation, and movement at the rear bay which appears historic but is not yet demonstrably dormant.</text:p>
  <text:p text:style-name="Quote">No evidence was found of subsidence affecting the main frame. The cracking recorded at 3.2 is consistent with thermal movement rather than foundation failure.</text:p>
  <text:h text:style-name="Heading_20_1" text:outline-level="1">2. Scope and limitations</text:h>
  <text:p text:style-name="Standard">This survey covers the visible and accessible fabric of the building. Floors were not lifted and services were not tested. Where access was restricted the limitation is recorded against the relevant element below.</text:p>
  <text:h text:style-name="Heading_20_2" text:outline-level="2">2.1 Elements inspected</text:h>
  <text:list><text:list-item><text:p text:style-name="Standard">Roof covering, rainwater goods and parapet detail</text:p></text:list-item>
  <text:list-item><text:p text:style-name="Standard">External walls, openings and lintels</text:p></text:list-item>
  <text:list-item><text:p text:style-name="Standard">Internal partitions, ceilings and floor surfaces</text:p></text:list-item>
  <text:list-item><text:p text:style-name="Standard">Sub-floor void, where an access hatch existed</text:p></text:list-item></text:list>
  <text:h text:style-name="Heading_20_1" text:outline-level="1">3. Findings by element</text:h>
  <table:table table:name="Findings">
   <table:table-column table:number-columns-repeated="4"/>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Element</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Condition</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Priority</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Estimate</text:p></table:table-cell>
   </table:table-row>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Parapet flashing, north</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Defective</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Within 12 months</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>£3,400</text:p></table:table-cell>
   </table:table-row>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Rear bay, movement</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Monitor</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Review at 6 months</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>—</text:p></table:table-cell>
   </table:table-row>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Rainwater goods</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Serviceable</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Routine</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>£280</text:p></table:table-cell>
   </table:table-row>
  </table:table>
  <text:p text:style-name="Standard">Full photographic record is appended at section 7. Recommendations are costed at current rates and exclude access equipment.</text:p>
 </office:text></office:body>
</office:document>
"""


def _cell(v, kind="float", cached=None, fmt=None, style=None):
    """One cell. A formula cell carries BOTH the formula and its cached value.

    Calc does not recalculate a foreign ODF on load by default, so a formula
    cell with no cached value renders as Err:510 ("missing variable") rather
    than a number - which is what the first two attempts at this file did. The
    formula is real and live; the cached value is what a genuine producer would
    have written, and it is what makes the sheet correct the instant it opens.
    """
    if kind == "string":
        return ('<table:table-cell office:value-type="string"><text:p>%s</text:p>'
                '</table:table-cell>' % v)
    if kind == "formula":
        shown = fmt if fmt is not None else ("%g" % cached)
        st = (' table:style-name="%s"' % style) if style else ""
        return ('<table:table-cell%s table:formula="of:=%s" '
                'office:value-type="percentage" office:value="%s">'
                '<text:p>%s</text:p></table:table-cell>'
                % (st, v, cached, shown)) if style == "Pct" else (
               '<table:table-cell table:formula="of:=%s" '
               'office:value-type="float" office:value="%s">'
               '<text:p>%s</text:p></table:table-cell>' % (v, cached, shown))
    return ('<table:table-cell office:value-type="float" office:value="%s">'
            '<text:p>%s</text:p></table:table-cell>' % (v, v))


def build_fods():
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    regions = [("North", 41200, 1.08), ("South", 38600, 1.11),
               ("East", 29400, 1.05), ("West", 33900, 1.14),
               ("Export", 18750, 1.22)]
    rows = ['<table:table-row>' + _cell("Region", "string")
            + "".join(_cell(m, "string") for m in months)
            + _cell("Total", "string") + _cell("Growth", "string")
            + '</table:table-row>']
    grid = []                       # the monthly numbers, kept for the totals
    for i, (name, base, growth) in enumerate(regions):
        r = i + 2
        vals = [int(base * (growth ** (m / 12.0))) for m in range(12)]
        grid.append(vals)
        cells = [_cell(name, "string")] + [_cell(v) for v in vals]
        total = sum(vals)
        cells.append(_cell("SUM([.B%d:.M%d])" % (r, r), "formula", cached=total))
        gr = vals[-1] / vals[0] - 1
        cells.append(_cell("[.M%d]/[.B%d]-1" % (r, r), "formula",
                           cached="%.6f" % gr, fmt="%.1f%%" % (gr * 100),
                           style="Pct"))
        rows.append('<table:table-row>' + "".join(cells) + '</table:table-row>')

    r = len(regions) + 2
    foot = ['<table:table-row>' + _cell("All regions", "string")]
    for j, c in enumerate("BCDEFGHIJKLM"):
        foot.append(_cell("SUM([.%s2:.%s%d])" % (c, c, r - 1), "formula",
                          cached=sum(row[j] for row in grid)))
    foot.append(_cell("SUM([.N2:.N%d])" % (r - 1), "formula",
                      cached=sum(sum(row) for row in grid)))
    foot.append(_cell("", "string"))
    rows.append("".join(foot) + '</table:table-row>')

    return """<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
 xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0"
 office:version="1.3"
 office:mimetype="application/vnd.oasis.opendocument.spreadsheet">
 <office:automatic-styles>
  <number:percentage-style style:name="PctFmt">
   <number:number number:decimal-places="1" number:min-integer-digits="1"/>
   <number:text>%%</number:text>
  </number:percentage-style>
  <style:style style:name="Pct" style:family="table-cell"
   style:data-style-name="PctFmt"/>
 </office:automatic-styles>
 <office:body><office:spreadsheet>
  <table:table table:name="Revenue by region">
   <table:table-column table:number-columns-repeated="15"/>
   %s
  </table:table>
  <table:table table:name="Assumptions"/>
  <table:table table:name="Notes"/>
 </office:spreadsheet></office:body>
</office:document>
""" % "\n   ".join(rows)


def _slide(name, title, bullets):
    body = "".join('<text:p text:style-name="Body">%s</text:p>' % b
                   for b in bullets)
    return """
   <draw:page draw:name="%s" draw:master-page-name="Default"
    draw:style-name="PageStyle">
    <draw:frame draw:style-name="FrameNoFill" presentation:class="title"
     svg:width="22cm" svg:height="2.6cm" svg:x="1.8cm" svg:y="1.4cm">
     <draw:text-box><text:p text:style-name="SlideTitle">%s</text:p></draw:text-box>
    </draw:frame>
    <draw:frame draw:style-name="FrameNoFill" presentation:class="outline"
     svg:width="22cm" svg:height="9cm" svg:x="1.8cm" svg:y="4.8cm">
     <draw:text-box>%s</draw:text-box>
    </draw:frame>
   </draw:page>""" % (name, title, body)


def build_fodp():
    slides = (
        _slide("Cover", "Northwind Terrace",
               ["Structural survey findings", "Marlow &amp; Finch LLP",
                "14 August 2026"])
        + _slide("Summary", "What we found",
                 ["Structure is sound; no subsidence in the main frame",
                  "Two items need attention inside twelve months",
                  "Estimated remedial cost: £3,680",
                  "Rear bay to be re-measured at six months"])
        + _slide("Priorities", "Recommended sequence",
                 ["1 — Parapet flashing, north elevation",
                  "2 — Rainwater goods, routine clearance",
                  "3 — Monitor rear bay movement",
                  "4 — Re-inspect after the winter"])
        + _slide("Next", "Decisions we need",
                 ["Approve the flashing works",
                  "Confirm access arrangements",
                  "Agree the six-month review date"]))
    return """<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
 xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
 xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
 xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
 office:version="1.3"
 office:mimetype="application/vnd.oasis.opendocument.presentation">
 <office:styles>
  <style:style style:name="FrameNoFill" style:family="graphic">
   <style:graphic-properties draw:fill="none" draw:stroke="none"
    draw:auto-grow-height="false" fo:padding="0cm"/>
  </style:style>
  <style:style style:name="SlideTitle" style:family="paragraph">
   <style:text-properties fo:font-size="30pt" fo:font-weight="bold"
    fo:color="#1a2130"/>
  </style:style>
  <style:style style:name="Body" style:family="paragraph">
   <style:paragraph-properties fo:margin-bottom="0.45cm"/>
   <style:text-properties fo:font-size="18pt" fo:color="#3a4152"/>
  </style:style>
  <style:style style:name="PageStyle" style:family="drawing-page">
   <style:drawing-page-properties draw:fill="solid" draw:fill-color="#ffffff"/>
  </style:style>
 </office:styles>
 <office:body><office:presentation>%s
 </office:presentation></office:body>
</office:document>
""" % slides


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    files = {"survey-report.fodt": FODT,
             "revenue-by-region.fods": build_fods(),
             "survey-findings.fodp": build_fodp()}
    for name, body in files.items():
        p = os.path.join(out, name)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
        print("  %-26s %6d B" % (name, os.path.getsize(p)))
    print("written to", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
