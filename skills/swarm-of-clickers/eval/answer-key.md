# Answer key: the Tallyleaf fixture

Tallyleaf is a fictional invoicing tool: three static pages (`index.html` invoices, `settings.html`, `reports.html`) served from `fixture/`. It carries 20 seeded defects, ids K01 to K20. A clicker never confirms Save, Submit, Delete, Send, Apply or Import and the guard blocks every write, so every defect can be found by looking, clicking tabs, filters, sorts and checkboxes, and reading the console.

Widths: 1280 unless the description gives another. Schemes: light unless said.

| id | category | page | element | description |
|---|---|---|---|---|
| K01 | measurable | index | The "Month notes" text field in the right-hand column | The field is wider than its card: it sticks out about 26 px past the card's right edge, at 1280 and at 390. Visible in the first screen. |
| K02 | measurable | settings | The hint under "Mailing address" on the Profile tab ("Printed under your business name. Leave blank to hide it.") | Pale grey text on white, contrast about 2.2:1 against the 4.5:1 needed. Light scheme only; in the dark scheme it reads fine. |
| K03 | measurable | reports | The "Updated 4 min ago" stamp on the "Revenue by client, this period" card | The stamp is drawn over the end of the card's heading, so the two texts collide. At 1280 only; at 390 the stamp sits below the heading. |
| K04 | measurable | settings | The pencil (Edit) and cross (Remove) icon buttons in each Team members row | Each is 18x18 px and they sit 2 px apart, under the 24 px target size with no spacing. Same at 390. |
| K05 | measurable | index | The leaf logo image at the left of the header | The `<img>` has no alt attribute. Only on this page; the other two pages mark it decorative. |
| K06 | measurable | reports | The page itself, on load | Loading the page logs a console error: a request for `api/usage-summary.json` fails with 404 and the script that reads it throws. Nothing on screen changes. Only when the fixture is served over http; the page still works. |
| K07 | visual | index | The icon in the "Overdue" summary tile | The icon circle sits about 8 px lower than the icons in the other three tiles. |
| K08 | visual | reports | The three cards under the period buttons (Invoiced, Collected, Average days to pay) | The gap before the third card ("Average days to pay") is about 30 px, the gap between the first two is 16 px. At 390, the third card is also indented 14 px. |
| K09 | visual | index, reports | The "Export CSV" button on Invoices and the "Download CSV" button on Reports | One action, two labels: both produce the same invoices.csv, and each shows the same "invoices.csv is ready" message beside the button. |
| K10 | visual | settings | The "Late Fee Percentage" label on the Invoicing tab | Title Case, while the other labels on the tab ("Default currency", "Payment terms", "Invoice number prefix", "Reminder days before due") are sentence case. |
| K11 | visual | index | The Amount column of the invoice table | The amounts end about 20 px to the left of the right edge of the "Amount" header, so the column and its header do not line up. |
| K12 | visual | reports | The "Beta" tag next to the "Reports" heading | The tag sits about 7 px above the heading's baseline, not aligned with the heading text. |
| K13 | UX | index | The "Copy link to this view" button above the table | Clicking it gives no feedback: no message, no change of label. "Export CSV" next to it confirms with a message. |
| K14 | UX | settings | The Integrations tab | Click Integrations: the panel says only "No integrations connected." It offers no way to connect one and no explanation of where to do it. |
| K15 | UX | index | The "Quick invoice" card's steps | The steps run "1 Review totals", "2 Add line items", "3 Choose client": the totals are reviewed before there are any line items or a client. Click Next twice to see the order. |
| K16 | UX | reports | The icon-only button with three horizontal lines at the right of the period buttons | It has no text, no tooltip and no accessible name. Clicking it tightens the row spacing of the "Open invoices by age" table, which nothing on the page says. |
| K17 | functional | settings | The "Default currency" select on the Invoicing tab | Steps: open Invoicing, choose Euro, open Notifications, open Invoicing again. The select is back on US dollar. The "Payment terms" select next to it keeps its value. |
| K18 | functional | index | The "Status" filter's "Overdue" option | Choose Overdue: the table still shows all 12 invoices and says "Showing 12 of 12 invoices". Draft, Sent and Paid filter correctly. |
| K19 | functional | index | The sort buttons in the table header (steps use "Status") | Sorting does not keep equal rows in their previous order. From the first load, click the Status header: within each status the invoice numbers run high to low (the list was low to high before). Click it again and they run low to high. |
| K20 | functional | index | The "N selected" counter | Tick the checkbox in the table header to select all: the counter reads 13 selected with 12 rows shown (it counts the header checkbox). Ticking single rows counts correctly. |

Totals: 6 measurable, 6 visual, 4 UX, 4 functional.

## Expected check hits

The hit kinds `look.sh checks` returns for each page's first screen, served over http, each with its number of hits (`limit` notes are not counted). An empty cell means none. Nothing else on these pages may produce a hit; if one does, the fixture has a key error.

| page | 1280 light | 390 light | 1280 dark |
|---|---|---|---|
| index | img-alt 1, overflow 1 | img-alt 1, overflow 1 | img-alt 1, overflow 1 |
| settings | contrast 1, small-target 4 | contrast 1, small-target 4 | small-target 4 |
| reports | console-error 1, overlap 1 | console-error 1 | console-error 1, overlap 1 |

The six kinds are covered by the 1280 light column: overflow, img-alt (index), contrast, small-target (settings), overlap, console-error (reports).
