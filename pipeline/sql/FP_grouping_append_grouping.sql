-- Append "grouping" column to savvy-gtm-analytics.ml_features.FP_grouping
-- Joins: FP_grouping.CRD (person) -> ria_contacts_current.RIA_CONTACT_CRD_ID
--        ria_contacts_current.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID -> ria_firms_current.CRD_ID
-- Groups:
--   Independent advisor: firm has <= 5 advisors (EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH)
--   Small RIA: firm has <= 15 advisors OR firm TOTAL_AUM < 1 billion dollars
--   Everyone else: rest (including no firm match)
--
-- Run this to replace the table with the same data plus the new "grouping" column, then export.

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.FP_grouping` AS
SELECT
  g.*,
  CASE
    WHEN f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
         AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 5
      THEN 'Independent advisor'
    WHEN (f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH IS NOT NULL
          AND f.EMPLOYEE_PERFORM_INVESTMENT_ADVISORY_FUNCTIONS_AND_RESEARCH <= 15)
      OR (f.TOTAL_AUM IS NOT NULL AND f.TOTAL_AUM < 1000000000)
      THEN 'Small RIA'
    ELSE 'Everyone else'
  END AS `grouping`
FROM `savvy-gtm-analytics.ml_features.FP_grouping` g
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current` c
  ON g.CRD = c.RIA_CONTACT_CRD_ID
LEFT JOIN `savvy-gtm-analytics.FinTrx_data_CA.ria_firms_current` f
  ON c.LATEST_REGISTERED_EMPLOYMENT_COMPANY_CRD_ID = f.CRD_ID;
