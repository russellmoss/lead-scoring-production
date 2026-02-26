-- Enrich FP_prospect_and_opp_check with Lead (prospect) and Opportunity IDs and disposition/closed-lost fields.
-- Match: CRD (ml_features) = FA_CRD__c (Lead and Opportunity). One lead and one opportunity per CRD (arbitrary if multiple).
-- Adds columns: prospect_id, opportunity_id, disposition__c, closed_lost_details__c, closed_lost_reason__c.

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.FP_prospect_and_opp_check` AS
WITH
-- One lead per FA_CRD__c (pick one if multiple)
lead_one AS (
  SELECT
    FA_CRD__c,
    Full_Prospect_ID__c AS prospect_id,
    Disposition__c AS disposition__c
  FROM (
    SELECT
      FA_CRD__c,
      Full_Prospect_ID__c,
      Disposition__c,
      ROW_NUMBER() OVER (PARTITION BY FA_CRD__c ORDER BY LastModifiedDate DESC NULLS LAST, Id) AS rn
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
    WHERE IsDeleted = FALSE
      AND FA_CRD__c IS NOT NULL
  )
  WHERE rn = 1
),
-- One opportunity per FA_CRD__c (pick one if multiple)
opp_one AS (
  SELECT
    FA_CRD__c,
    Full_Opportunity_ID__c AS opportunity_id,
    Closed_Lost_Details__c AS closed_lost_details__c,
    Closed_Lost_Reason__c AS closed_lost_reason__c
  FROM (
    SELECT
      FA_CRD__c,
      Full_Opportunity_ID__c,
      Closed_Lost_Details__c,
      Closed_Lost_Reason__c,
      ROW_NUMBER() OVER (PARTITION BY FA_CRD__c ORDER BY LastModifiedDate DESC NULLS LAST, Id) AS rn
    FROM `savvy-gtm-analytics.SavvyGTMData.Opportunity`
    WHERE IsDeleted = FALSE
      AND FA_CRD__c IS NOT NULL
  )
  WHERE rn = 1
)
SELECT
  f.*,
  l.prospect_id,
  o.opportunity_id,
  l.disposition__c,
  o.closed_lost_details__c,
  o.closed_lost_reason__c
FROM `savvy-gtm-analytics.ml_features.FP_prospect_and_opp_check` f
LEFT JOIN lead_one l
  ON SAFE_CAST(f.CRD AS STRING) = l.FA_CRD__c
LEFT JOIN opp_one o
  ON SAFE_CAST(f.CRD AS STRING) = o.FA_CRD__c;
