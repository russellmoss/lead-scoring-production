# List Enrichment When You Have Name, LinkedIn and Firm 

**Purpose:** A reusable playbook for taking any list of financial advisors (conference attendees, event registrants, purchased lists, etc.) and enriching it with FinTrx data, lead scores, and Salesforce disposition history. Follow these steps in order — each phase builds on the previous one.

---

## What You Start With

A list (CSV, Google Sheet, or export) with some combination of:

- **Name** (first \+ last, or full name)  
- **Company / Firm name**  
- **Title**  
- **LinkedIn URL**

Not every row will have every field. That's fine — the pipeline is designed to handle gaps.

## What You End With

Every advisor you can confidently identify gets:

- **CRD number** (the unique advisor identifier in FinTrx and FINRA)  
- **FinTrx profile data** — firm AUM, rep AUM, producing advisor status, age range, disclosures, title  
- **Lead scores** — V3 tier and V4 percentile from the scoring pipeline  
- **Exclusion narrative** — if they don't score, exactly why (age, disclosures, title, firm, etc.)  
- **Salesforce history** — whether we've contacted them before, disposition, close lost reason/detail

---

## 

## Phase 1: LinkedIn URL Matching

**Goal:** Match as many rows as possible using LinkedIn URLs. This is the highest-confidence method.

### Why LinkedIn first

LinkedIn profile URLs are effectively unique identifiers. If someone's LinkedIn URL in your list matches one in FinTrx, you can be very confident that's the same person. This avoids all the ambiguity of name matching.

### URL normalization

Both the list URL and the FinTrx `LINKEDIN_PROFILE_URL` must be normalized to the same canonical form before comparison:

1. Lowercase everything  
2. Strip protocol (`https://`, `http://`)  
3. Strip `www.`  
4. Strip trailing slashes  
5. Strip query parameters (`?locale=en_US`, tracking params, etc.)  
6. Strip fragments (`#anchor`)

**Result:** `linkedin.com/in/username`

**Example:**

```
Input:    https://www.LinkedIn.com/in/JohnSmith/?utm_source=conference
Normalized: linkedin.com/in/johnsmith
```

### Matching process

1. Normalize all LinkedIn URLs in your attendee list  
2. Query FinTrx `ria_contacts_current` with normalized URLs  
3. On match: extract `RIA_CONTACT_CRD_ID` (the advisor's CRD)

### Confidence signals

When a LinkedIn URL matches, you can further validate by checking whether the name and/or firm also align. This gives you a confidence taxonomy:

| Match type | Confidence | What matched |
| :---- | :---- | :---- |
| `linkedin + name + firm` | Highest | URL, name, and firm all confirmed |
| `linkedin + name` | Very high | URL \+ name match; firm differs (advisor may have moved) |
| `linkedin + firm` | High | URL \+ firm match; name differs (name variant, maiden name) |
| `linkedin` | Good | URL only — name and firm didn't confirm |

**Rule:** Never match on firm alone. Firm names are not unique and are only used as a supporting confidence signal.

### Handling the results

- Rows with a LinkedIn match → CRD is assigned, move to Phase 3  
- Rows without a LinkedIn match (no URL, or URL not in FinTrx) → move to Phase 2

---

## Phase 2: Name Matching (Fallback)

**Goal:** For rows that didn't match on LinkedIn, attempt to find the advisor in FinTrx by name. Only assign a CRD when there is exactly one match.

### Why strict single-match only

Name matching is inherently less reliable than LinkedIn. "John Smith" could be dozens of advisors. The single-match rule ensures you only enrich when you're confident it's the right person. False positives are worse than missed matches — you can always manually review unmatched rows later.

### 

### How name matching works

**Step 1: Parse the name**

Split into first name and last name. Simple approach: first word \= first name, everything after \= last name.

- `"Wayne Anderman"` → first: `Wayne`, last: `Anderman`  
- `"Mary Jane Watson"` → first: `Mary`, last: `Jane Watson`

**Step 2: Query FinTrx with nickname awareness**

Match on `CONTACT_LAST_NAME` (exact) AND any of three first-name fields:

| FinTrx field | What it catches |
| :---- | :---- |
| `CONTACT_FIRST_NAME` | Standard first name (e.g., `Robert`) |
| `RIA_CONTACT_FIRST_NAME_OTHER` | Alternate/nickname (e.g., `Bob` for Robert, `Rich` for Richard) |
| `RIA_CONTACT_PREFERRED_NAME` | Preferred full name — matched against the full name string |

This handles common nickname variations without needing an explicit nickname lookup table:

- Bob → Robert  
- Rich → Richard  
- Bill → William  
- Jim → James  
- Mike → Michael  
- Liz → Elizabeth  
- etc.

FinTrx already stores these variants, so querying all three fields catches them naturally.

**Step 3: Apply the uniqueness rule**

| Matches found | Action |
| :---- | :---- |
| **0** | No enrichment. Mark as unmatched. |
| **1** | Enrich. Assign CRD and backfill FinTrx data. |
| **2+** | Do not enrich. Flag as `(multiple matches)` for manual review. |

### What gets backfilled on a single match

- `CRD` — the advisor's CRD number  
- `LINKEDIN_PROFILE_URL` — from FinTrx (if available, useful for future matching)  
- `PRIMARY_FIRM_TOTAL_AUM` — firm-level AUM  
- `REP_AUM` — individual advisor AUM  
- `PRODUCING_ADVISOR` — TRUE/FALSE

### Important behaviors

- **Never overwrite Phase 1 matches.** If a row already has a CRD from LinkedIn matching, skip it entirely. LinkedIn matches are trusted.  
- **Firm can be used as a tiebreaker for manual review** of multiple-match rows, but never as the sole matching criterion in the automated pipeline.

---

## Phase 3: FinTrx Enrichment

**Goal:** Now that you have CRDs, pull the full advisor and firm profile from FinTrx.

### Data sources

| Table | Key field | What you get |
| :---- | :---- | :---- |
| `FinTrx_data_CA.ria_contacts_current` | `RIA_CONTACT_CRD_ID` | Advisor-level data: name, title, age range, disclosures, LinkedIn URL, rep AUM, firm affiliation |
| `FinTrx_data_CA.ria_firms_current` | `CRD_ID` (join via `PRIMARY_FIRM`) | Firm-level data: total AUM, discretionary AUM, number of advisors, firm type |

### Key fields to extract

**From `ria_contacts_current` (advisor level):**

- `CONTACT_FIRST_NAME`, `CONTACT_LAST_NAME` — canonical name  
- `TITLE_NAME` — current title  
- `PRIMARY_FIRM_NAME` — firm they're registered with  
- `PRIMARY_FIRM` — firm CRD (used to join to firm table)  
- `AGE_RANGE` — age bracket  
- `REP_AUM` — individual AUM  
- `PRODUCING_ADVISOR` — whether they're a producing advisor  
- `LINKEDIN_PROFILE_URL` — their LinkedIn  
- `CONTACT_HAS_DISCLOSED_*` — disclosure flags (criminal, regulatory, termination, investigation, customer dispute, civil, bond)

**From `ria_firms_current` (firm level):**

- `TOTAL_AUM` — firm total AUM  
- `DISCRETIONARY_AUM` — firm discretionary AUM (used to calculate discretionary ratio)  
- Firm metadata (type, registration status, etc.)

### CRD type casting

FinTrx stores CRDs inconsistently (sometimes as strings, floats, or integers). Always normalize with this pattern in SQL:

```sql
SAFE_CAST(ROUND(SAFE_CAST(RIA_CONTACT_CRD_ID AS FLOAT64), 0) AS INT64)
```

Use this same pattern everywhere you join on CRD — in FinTrx queries, scoring queries, and Salesforce lookups.

---

## Phase 4: Lead Scoring

**Goal:** Run every matched CRD through the V3+V4 scoring pipeline to get a tier and percentile.

### How it works

1. Upload all unique CRDs to a BigQuery staging table  
2. Run the lead list scoring SQL (e.g., `January_2026_Lead_List_V3_V4_Hybrid.sql`) restricted to your CRD list  
3. The query injects an `input_crds` CTE to filter `base_prospects` to only your list  
4. Scores are merged back into your CSV

### Output columns

| Column | Description |
| :---- | :---- |
| `score_tier` | V3 tier (e.g., Tier 1, Tier 2, Tier 3). Only populated if the advisor passes all pipeline filters. |
| `v4_score` | Raw V4 model score |
| `v4_percentile` | V4 percentile rank (higher \= better fit for Savvy) |
| `narrative` | V3 scoring narrative OR a specific exclusion reason |

### Exclusion diagnostics

For any advisor who doesn't receive a `score_tier`, the narrative tells you exactly which filter excluded them, checked in this order:

1. **Not in FinTrx** — CRD doesn't exist in `ria_contacts_current`  
2. **Age over 70** — age range is 70+  
3. **Disclosures** — criminal, regulatory, termination, investigation, customer dispute, civil, or bond  
4. **Title excluded** — paraplanner, operations, wholesaler, compliance, assistant, insurance agent, CFO, CIO, VP, etc.  
5. **Firm excluded** — wirehouse/BD/insurance name pattern match, or specific firm CRD on exclusion list  
6. **Base exclusion** — not a producing advisor, missing required fields  
7. **Turnover ≥ 100%** — firm has full advisor turnover  
8. **Low discretionary AUM** — firm discretionary ratio below 50%  
9. **Recent promotee** — less than 5 years tenure with mid/senior title  
10. **No V4 score** — not in the V4 prospect universe  
11. **V4 bottom 20%** — deprioritized due to low V4 percentile

If the advisor has a V4 score but was excluded for a different reason, the narrative includes both (e.g., `"Title excluded. Has V4 score (percentile 72)."`).

---

## Phase 5: Salesforce History Lookup

**Goal:** Check whether we've already contacted, qualified, or lost each advisor — and if so, why.

### How the CRD maps to Salesforce

The CRD number links to Salesforce via the `fa_crd__c` custom field, which exists on both the **Lead** and **Opportunity** objects.

### What to extract

**From Lead object (`Lead`):**

| Field | What it tells you |
| :---- | :---- |
| `fa_crd__c` | The advisor CRD (your join key) |
| `Status` | Current lead status (e.g., New, Working, Qualified, Disqualified) |
| `Disposition__c` | The disposition outcome (e.g., Interested, Not Interested, No Answer, Bad Data) |

**From Opportunity object (`Opportunity`):**

| Field | What it tells you |
| :---- | :---- |
| `fa_crd__c` | The advisor CRD (your join key) |
| `StageName` | Current opportunity stage |
| `IsClosed` | Whether the opportunity is closed |
| `IsWon` | Whether it was won |
| `Close_Lost_Reason__c` | Why we lost (e.g., Timing, Compensation, Technology, Compliance) |
| `Close_Lost_Detail__c` | Free-text detail on the loss reason |
| `Disposition__c` | Disposition if applicable |

### Query approach

You can query Salesforce data in two ways:

**Option A: SOQL (direct Salesforce query)**

```sql
SELECT fa_crd__c, Status, Disposition__c
FROM Lead
WHERE fa_crd__c IN ('1234567', '7654321', ...)
```

```sql
SELECT fa_crd__c, StageName, IsClosed, IsWon,
       Close_Lost_Reason__c, Close_Lost_Detail__c, Disposition__c
FROM Opportunity
WHERE fa_crd__c IN ('1234567', '7654321', ...)
```

**Option B: BigQuery (if Salesforce data is synced)**

If Salesforce data is replicated to BigQuery (e.g., via Fivetran, Stitch, or a custom sync), query the replicated `lead` and `opportunity` tables with the same CRD join logic.

### How to use the Salesforce data

This lookup tells you:

- **Has this advisor been contacted before?** If their CRD appears in Lead or Opportunity, yes.  
- **What happened?** The disposition and close lost reason tell you why it didn't convert.  
- **Should we re-engage?** An advisor who was "Not Interested — Timing" a year ago may be worth re-contacting. An advisor who was "Not Interested — Not an RIA" is probably not.

Merge this data into your scored CSV so the outreach team has full context before making calls.

---

## General Workflow Checklist

Use this checklist every time you run this pipeline on a new list.

### Preparation

- [ ] Source list exported as CSV or Google Sheet  
- [ ] Columns identified: name, LinkedIn URL, firm, title (not all required)  
- [ ] `gcloud auth application-default login` is active  
- [ ] Dependencies installed (`google-cloud-bigquery`, `pandas`)  
- [ ] Lead list scoring SQL is current in `pipeline/sql/`

### Phase 1 — LinkedIn URL matching

- [ ] Normalize all LinkedIn URLs in the list  
- [ ] Query FinTrx `ria_contacts_current` by normalized URL  
- [ ] Assign CRDs for all matches  
- [ ] Record match confidence (`linkedin + name + firm`, `linkedin + name`, etc.)

### Phase 2 — Name matching (fallback)

- [ ] Identify rows still missing a CRD  
- [ ] Query FinTrx by first \+ last name (including nickname fields)  
- [ ] Apply single-match rule: only assign CRD if exactly one result  
- [ ] Flag multiple-match rows for manual review

### Phase 3 — FinTrx enrichment

- [ ] Pull advisor data from `ria_contacts_current` by CRD  
- [ ] Pull firm data from `ria_firms_current` by firm CRD  
- [ ] Merge AUM, title, age, disclosure flags, etc. into the list

### Phase 4 — Lead scoring

- [ ] Upload CRDs to BigQuery staging table  
- [ ] Run V3+V4 scoring pipeline restricted to your CRDs  
- [ ] Merge `score_tier`, `v4_score`, `v4_percentile`, `narrative` into the list  
- [ ] Review exclusion narratives for excluded advisors

### Phase 5 — Salesforce history

- [ ] Query Lead object by `fa_crd__c` for status and disposition  
- [ ] Query Opportunity object by `fa_crd__c` for stage, close lost reason, close lost detail  
- [ ] Merge Salesforce history into the list  
- [ ] Flag previously contacted advisors for the outreach team

### Final output

- [ ] Import scored \+ enriched CSV back to Google Sheets  
- [ ] Sort by `score_tier` and `v4_percentile` for outreach prioritization  
- [ ] Share with outreach team with context on match confidence and Salesforce history

---

## Tips & Gotchas

**CRD type casting:** FinTrx stores CRDs inconsistently. Always use `SAFE_CAST(ROUND(SAFE_CAST(x AS FLOAT64), 0) AS INT64)` in every join. This handles strings, floats, and integers.

**Duplicate columns:** If your CSV already has empty score columns from a prior run, the scoring script appends new ones. Delete the empty originals first, or clean up after.

**Path sensitivity:** Run scripts from the project root (`lead_scoring_production/`). Running from a subdirectory doubles up relative paths.

**BigQuery MCP limitation:** The BQ MCP tool in Cursor only returns one row per query. Always run multi-row BQ queries in BigQuery Console and export results.

**Name parsing edge cases:** The first-word/rest split doesn't handle suffixes (Jr., III) or hyphenated first names well. For high-value lists, manually review unmatched names.

**Firm name normalization:** Firm names in attendee lists rarely match FinTrx exactly (`"Merrill Lynch"` vs `"Merrill Lynch, Pierce, Fenner & Smith"`). This is why firm is never used as a primary match — only as a confidence signal.

**Re-running on updated lists:** If the attendee list grows (e.g., late registrations), you can re-run the full pipeline. Phase 1 and 2 will skip rows that already have CRDs, so only new rows get processed.  
