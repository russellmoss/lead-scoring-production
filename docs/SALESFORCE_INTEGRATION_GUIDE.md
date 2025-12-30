# Salesforce Integration Guide

**Purpose**: Document Salesforce sync scripts and process for lead scoring  
**Status**: ✅ Production  
**Version**: 1.0  
**Last Updated**: December 30, 2025

---

## Executive Summary

The Salesforce Integration syncs lead scoring results from BigQuery to Salesforce Lead and Opportunity records. This enables the sales team to see model scores, tiers, and recommendations directly in Salesforce.

**Two Integration Points**:
1. **V3 Rules-Based Scores**: Tier assignments and expected conversion rates
2. **V4 ML Scores**: Percentile ranks and deprioritization flags

---

## Architecture

### Data Flow

```
BigQuery Tables
    │
    ├── ml_features.lead_scores_v3 (V3 tier scores)
    │
    ├── ml_features.v4_daily_scores_v41 (V4 ML scores)
    │
    └── ml_features.january_2026_lead_list (Hybrid lead list)
         │
         ▼
    Python Sync Scripts
         │
         ▼
    Salesforce API
         │
         ▼
    Lead/Opportunity Records
```

### Salesforce Custom Fields

**V3 Fields** (Lead Object):
- `Lead_Score_Tier__c` - Tier assignment (e.g., 'TIER_1A_PRIME_MOVER_CFP')
- `Lead_Tier_Display__c` - Human-readable tier name
- `Expected_Conversion__c` - Expected conversion rate (e.g., '16.44%')
- `Expected_Lift__c` - Expected lift vs baseline (e.g., '4.30x')
- `Lead_Priority_Rank__c` - Priority ranking (1 = highest)
- `Lead_Action__c` - Recommended action
- `Lead_Score_Explanation__c` - Narrative explanation
- `Lead_Model_Version__c` - Model version (e.g., 'V3.3.0')
- `Lead_Scored_At__c` - Timestamp of scoring

**V4 Fields** (Lead Object):
- `V4_Score__c` - Raw prediction (0-1)
- `V4_Score_Percentile__c` - Percentile rank (1-100)
- `V4_Deprioritize__c` - Boolean (TRUE if percentile <= 20)
- `V4_Model_Version__c` - Model version (e.g., 'v4.1.0')
- `V4_Scored_At__c` - Timestamp of scoring

---

## SQL Queries

### V3 Salesforce Sync Query

**File**: `v3/sql/phase_7_salesforce_sync.sql`

**Purpose**: Generate update payloads for V3 tier scores

**Query**:
```sql
SELECT 
    lead_id as Id,
    score_tier as Lead_Score_Tier__c,
    tier_display as Lead_Tier_Display__c,
    CAST(expected_conversion_rate * 100 AS STRING) || '%' as Expected_Conversion__c,
    CAST(expected_lift AS STRING) || 'x' as Expected_Lift__c,
    priority_rank as Lead_Priority_Rank__c,
    action_recommended as Lead_Action__c,
    tier_explanation as Lead_Score_Explanation__c,
    model_version as Lead_Model_Version__c,
    scored_at as Lead_Scored_At__c
FROM `savvy-gtm-analytics.ml_features.lead_scores_v3`
WHERE score_tier != 'STANDARD'
    AND contacted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)  -- Only sync recent leads
```

**Usage**: Run this query to get scores, then use Python script to sync to Salesforce

### V4.1 Salesforce Sync Query

**File**: `v4/sql/v4.1/salesforce_sync_v41.sql`

**Purpose**: Generate update payloads for V4.1.0 ML scores

**Query Structure**:
```sql
WITH scored_leads AS (
    SELECT 
        ds.lead_id,
        ds.advisor_crd,
        ds.prediction_date,
        ds.model_version,
        ds.scored_at,
        -- Calculate percentile from scores
        CURRENT_TIMESTAMP() as sync_timestamp
    FROM `savvy-gtm-analytics.ml_features.v4_daily_scores_v41` ds
    WHERE ds.model_version = 'v4.1.0'
      AND ds.lead_id IN (
          SELECT Id 
          FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
          WHERE Stage != 'MQL'  -- Only sync non-converted leads
      )
)
SELECT 
    lead_id as Id,
    v4_score as V4_Score__c,
    v4_percentile as V4_Score_Percentile__c,
    v4_deprioritize as V4_Deprioritize__c,
    model_version as V4_Model_Version__c,
    scored_at as V4_Scored_At__c
FROM scored_leads
WHERE scored_at >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)  -- Only sync recent scores
```

**Usage**: Run this query to get scores, then use Python script to sync to Salesforce

---

## Python Sync Scripts

### V4.1 Score and Sync Script

**File**: `v4/scripts/v4.1/score_and_sync_v41.py`

**Purpose**: End-to-end script to score leads and sync to Salesforce

**Steps**:
1. Load V4.1.0 model from `v4/models/v4.1.0_r3/model.pkl`
2. Fetch features from BigQuery (`ml_features.v4_prospect_features`)
3. Prepare features (categorical encoding, missing value handling)
4. Score leads using XGBoost model
5. Calculate percentiles
6. Save scores to BigQuery (`ml_features.v4_prospect_scores`)
7. Sync scores to Salesforce via API

**Usage**:
```bash
python v4/scripts/v4.1/score_and_sync_v41.py
```

### Salesforce Field Verification Script

**File**: `v4/scripts/v4.1/verify_salesforce_fields.py`

**Purpose**: Verify that required Salesforce custom fields exist

**Checks**:
- Field existence
- Field type (Number, Text, Checkbox, DateTime)
- Field length/precision (if applicable)

**Usage**:
```bash
python v4/scripts/v4.1/verify_salesforce_fields.py
```

**Required Fields**:
- `V4_Score__c` (Number, 18, 2)
- `V4_Score_Percentile__c` (Number, 18, 0)
- `V4_Deprioritize__c` (Checkbox)
- `V4_Model_Version__c` (Text, 50)
- `V4_Scored_At__c` (DateTime)

---

## Sync Process

### Monthly V3 Sync

**Frequency**: Monthly (after lead list generation)

**Steps**:
1. Run `v3/sql/phase_7_salesforce_sync.sql` in BigQuery
2. Export results to CSV or use Python script
3. Use Salesforce Bulk API or simple-salesforce library to update Lead records
4. Verify sync success (check field population in Salesforce)

### Daily V4 Sync

**Frequency**: Daily (after scoring)

**Steps**:
1. Run `v4/scripts/v4.1/score_and_sync_v41.py`
2. Script automatically:
   - Scores leads
   - Saves to BigQuery
   - Syncs to Salesforce
3. Verify sync success

### Hybrid Lead List Sync

**Frequency**: Monthly (after lead list generation)

**Source**: `ml_features.january_2026_lead_list`

**Fields to Sync**:
- V3 tier assignments
- V4 percentile scores
- Expected conversion rates
- Priority rankings
- SGA assignments

---

## Authentication

### Salesforce API Credentials

**Required**:
- Salesforce Username
- Salesforce Password + Security Token
- Salesforce Instance URL (e.g., `https://yourinstance.salesforce.com`)

**Storage**: Use environment variables or secure credential store

**Python Library**: `simple-salesforce`

**Example**:
```python
from simple_salesforce import Salesforce

sf = Salesforce(
    username='your_username',
    password='your_password',
    security_token='your_token',
    domain='login'  # or 'test' for sandbox
)
```

---

## Error Handling

### Common Issues

**1. Missing Fields**:
- **Error**: `INVALID_FIELD: No such column 'V4_Score__c'`
- **Fix**: Run `verify_salesforce_fields.py` to check field existence
- **Solution**: Create missing fields in Salesforce Setup

**2. Type Mismatches**:
- **Error**: `INVALID_TYPE: expected Number, got String`
- **Fix**: Ensure data types match Salesforce field definitions
- **Solution**: Cast values correctly in SQL query

**3. API Limits**:
- **Error**: `REQUEST_LIMIT_EXCEEDED`
- **Fix**: Implement rate limiting or use Bulk API
- **Solution**: Batch updates, add delays between requests

**4. Authentication Failures**:
- **Error**: `INVALID_LOGIN: Invalid username, password, security token`
- **Fix**: Verify credentials and security token
- **Solution**: Regenerate security token if needed

---

## Monitoring

### Sync Success Metrics

**Track**:
- Number of records synced
- Sync duration
- Error rate
- Field population rate (percentage of leads with scores)

### Validation Queries

**Check V3 Sync**:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNT(Lead_Score_Tier__c) as leads_with_tier,
    COUNT(Lead_Score_Tier__c) / COUNT(*) * 100 as population_rate
FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
WHERE CreatedDate >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

**Check V4 Sync**:
```sql
SELECT 
    COUNT(*) as total_leads,
    COUNT(V4_Score__c) as leads_with_v4_score,
    COUNT(V4_Score__c) / COUNT(*) * 100 as population_rate
FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
WHERE CreatedDate >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

---

## Best Practices

### Data Freshness

- **V3 Scores**: Sync monthly after lead list generation
- **V4 Scores**: Sync daily after scoring
- **Hybrid Lists**: Sync monthly after lead list generation

### Incremental Updates

- Only sync records updated in last 7-30 days
- Use `scored_at` or `contacted_date` filters
- Avoid full table scans

### Error Recovery

- Log all sync attempts
- Retry failed records
- Alert on high error rates

### Testing

- Test in Salesforce Sandbox first
- Verify field mappings
- Test with small sample before full sync

---

## Related Documentation

- `v3/sql/phase_7_salesforce_sync.sql` - V3 sync query
- `v4/sql/v4.1/salesforce_sync_v41.sql` - V4.1 sync query
- `v4/scripts/v4.1/score_and_sync_v41.py` - V4.1 sync script
- `v4/scripts/v4.1/verify_salesforce_fields.py` - Field verification script
- `README.md` - Salesforce integration section

---

**Document Status**: Production  
**Maintained By**: Data Science Team  
**Last Review**: December 30, 2025

