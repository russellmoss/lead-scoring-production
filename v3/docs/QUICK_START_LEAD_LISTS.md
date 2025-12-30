# Quick Start: Generate Lead Lists

**Model:** V3.2.1_12212025  
**Last Updated:** January 2025

---

## 🚀 Fastest Way: Use Python Script

```bash
# Generate February 2026 list (2400 leads, 180-day recyclable threshold)
cd "C:\Users\russe\Documents\Lead Scoring\Version-3"
python scripts/generate_lead_list.py february_2026_lead_list

# Custom parameters
python scripts/generate_lead_list.py march_2026_lead_list --limit 3000 --recyclable-days 90

# Dry run (generate SQL without executing)
python scripts/generate_lead_list.py february_2026_lead_list --dry-run
```

---

## 📝 Manual Method: BigQuery

### Step 1: Open Template
Open: `sql/generate_lead_list_v3.2.1.sql`

### Step 2: Replace Placeholders
Find and replace:
- `{TABLE_NAME}` → `february_2026_lead_list` (or your desired name)
- `{LEAD_LIMIT}` → `2400` (or your desired limit)
- `{RECYCLABLE_DAYS}` → `180` (or your threshold)

### Step 3: Execute in BigQuery
1. Open BigQuery Console
2. Paste the modified SQL
3. Click "Run"

### Step 4: Validate
```sql
-- Check tier distribution
SELECT 
    score_tier,
    COUNT(*) as count,
    ROUND(AVG(expected_conversion_rate) * 100, 2) as avg_rate
FROM `savvy-gtm-analytics.ml_features.february_2026_lead_list`
GROUP BY score_tier
ORDER BY 
    CASE score_tier
        WHEN 'TIER_1A_PRIME_MOVER_CFP' THEN 1
        WHEN 'TIER_1B_PRIME_MOVER_SERIES65' THEN 2
        WHEN 'TIER_1_PRIME_MOVER' THEN 3
        ELSE 99
    END;
```

---

## 📊 What You Get

### Output Table: `ml_features.{your_table_name}`

**Key Columns:**
- `advisor_crd` - Advisor identifier
- `first_name`, `last_name`, `email`, `phone` - Contact info
- `firm_name`, `firm_net_change_12mo` - Firm context
- `score_tier` - Tier assignment (TIER_1A_PRIME_MOVER_CFP, etc.)
- `priority_rank` - Numeric priority (1-8)
- `expected_conversion_rate` - Expected conversion (0.1644 = 16.44%)
- **`score_narrative`** - **Detailed explanation for SGAs** (includes certification context!)
- `has_cfp`, `has_series_65_only` - Certification flags
- `list_rank` - Final ranking (1 to limit)

### Lead Sources
1. **New Prospects** (not in Salesforce) - Prioritized
2. **Recyclable Leads** (180+ days no contact) - Secondary

### Tier Priority
1. **Tier 1A:** CFP at bleeding firm (16.44% conversion) 🔥
2. **Tier 1B:** Series 65 only + Tier 1 (16.48% conversion) 🔥
3. **Tier 1:** Standard Prime Movers (13.21% conversion)
4. **Tier 2-5:** Other priority tiers
5. **Standard:** Baseline (3.82% conversion)

---

## 🎯 Best Practices

### Monthly Generation
```bash
# First of each month
python scripts/generate_lead_list.py {month}_{year}_lead_list
```

### Recommended Settings
- **Lead Limit:** 2400 (80 leads/day for 30 days)
- **Recyclable Days:** 180 (6 months)
- **Firm Cap:** 50 leads per firm (automatic)

### Table Naming
- Format: `{month}_{year}_lead_list`
- Examples: `february_2026_lead_list`, `march_2026_lead_list`

---

## 📈 Expected Results

Based on V3.2.1 model:
- **~14 leads** in Tier 1A (CFP)
- **~90 leads** in Tier 1B (Series 65)
- **~187 leads** in Tier 1 (Standard)
- **~2,400 total** leads (ranked by priority)

---

## 🔍 Validation Queries

After generation, run these to validate:

```sql
-- 1. Tier distribution
SELECT score_tier, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.{your_table}`
GROUP BY score_tier
ORDER BY MIN(priority_rank);

-- 2. Source breakdown
SELECT prospect_type, COUNT(*) as count
FROM `savvy-gtm-analytics.ml_features.{your_table}`
GROUP BY prospect_type;

-- 3. Certification flags
SELECT 
    SUM(has_cfp) as cfp_count,
    SUM(has_series_65_only) as series65_count
FROM `savvy-gtm-analytics.ml_features.{your_table}`;

-- 4. Top 10 leads
SELECT 
    list_rank,
    first_name,
    last_name,
    firm_name,
    score_tier,
    expected_rate_pct,
    score_narrative
FROM `savvy-gtm-analytics.ml_features.{your_table}`
ORDER BY list_rank
LIMIT 10;
```

---

## 📚 Full Documentation

See `docs/LEAD_LIST_GENERATION_GUIDE.md` for:
- Detailed explanation of ranking logic
- Troubleshooting guide
- Integration with Salesforce
- Dashboard connections

---

## ⚡ Quick Reference

| Task | Command |
|------|---------|
| Generate list | `python scripts/generate_lead_list.py {table_name}` |
| Custom limit | `--limit 3000` |
| Custom recyclable | `--recyclable-days 90` |
| Dry run | `--dry-run` |
| View in BigQuery | `SELECT * FROM ml_features.{table_name} ORDER BY list_rank` |

