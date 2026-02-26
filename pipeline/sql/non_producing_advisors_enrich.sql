-- Enrich savvy-gtm-analytics.ml_features.non-producing-advisors with:
-- 1. Firm name from FinTrx (only where current firm is null/empty): CRD -> ria_contacts_current.RIA_CONTACT_CRD_ID -> PRIMARY_FIRM_NAME
-- 2. Grouping: Independent advisor (<=5), Small RIA (<=15 or <1B AUM), Everyone else (via ria_contacts -> ria_firms_current)
-- 3. CRM: prospect_id, opportunity_id, disposition__c, closed_lost_details__c, closed_lost_reason__c (Lead/Opportunity by FA_CRD__c)
--
-- Preserves existing column order. Run in BigQuery to replace the table.

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.non-producing-advisors` AS
WITH
-- One lead per FA_CRD__c (most recent)
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
-- One opportunity per FA_CRD__c (most recent)
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
  COALESCE(NULLIF(TRIM(n.firm), ''), c.PRIMARY_FIRM_NAME) AS firm,
  n.name,
  n.title,
  n.linkedin,
  n.CRD,
  n.PRIMARY_FIRM_TOTAL_AUM,
  n.REP_AUM,
  n.PRODUCING_ADVISOR,
  n.score_tier,
  n.Randomize,
  n.`Request made`,
  n.`score order`,
  n.v4_score,
  n.v4_percentile,
  n.narrative,
  CASE
    WHEN f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
         AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 5
      THEN 'Independent advisor'
    WHEN (f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
          AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 15)
      OR (f.TOTAL_AUM IS NOT NULL AND f.TOTAL_AUM < 1000000000)
      THEN 'Small RIA'
    ELSE 'Everyone else'
  END AS `grouping`,
  l.prospect_id,
  o.opportunity_id,
  l.disposition__c,
  o.closed_lost_details__c,
  o.closed_lost_reason__c
FROM `savvy-gtm-analytics.ml_features.non-producing-advisors` n
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
  ON n.CRD = c.RIA_CONTACT_CRD_ID
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f
  ON c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID = f.CRD_ID
LEFT JOIN lead_one l
  ON SAFE_CAST(n.CRD AS STRING) = l.FA_CRD__c
LEFT JOIN opp_one o
  ON SAFE_CAST(n.CRD AS STRING) = o.FA_CRD__c;
