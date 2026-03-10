
CREATE OR REPLACE VIEW `savvy-gtm-analytics.ml_features.lead_target_variable` AS

WITH contacted_leads AS (
    SELECT
        l.Id as lead_id,
        SAFE_CAST(REGEXP_REPLACE(CAST(l.FA_CRD__c AS STRING), r'[^0-9]', '') AS INT64) as advisor_crd,
        DATE(l.stage_entered_contacting__c) as contacted_date,
        DATE(l.Stage_Entered_Call_Scheduled__c) as mql_date,
        
        -- Maturity check: lead must be at least 43 days old as of analysis_date
        -- CRITICAL: Use fixed analysis_date instead of CURRENT_DATE() for reproducibility
        DATE_DIFF(DATE('2025-10-31'), DATE(l.stage_entered_contacting__c), DAY) as days_since_contact,
        
        -- Target variable with right-censoring protection
        CASE
            -- Too young to label - exclude from training
            WHEN DATE_DIFF(DATE('2025-10-31'), DATE(l.stage_entered_contacting__c), DAY) < 43
            THEN NULL  -- Right-censored, exclude
            
            -- Converted to MQL within window
            WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL
                 AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), 
                               DATE(l.stage_entered_contacting__c), DAY) <= 43
            THEN 1  -- Positive: converted within window
            
            -- Converted after window (treat as negative for within-window prediction)
            WHEN l.Stage_Entered_Call_Scheduled__c IS NOT NULL
                 AND DATE_DIFF(DATE(l.Stage_Entered_Call_Scheduled__c), 
                               DATE(l.stage_entered_contacting__c), DAY) > 43
            THEN 0  -- Negative: didn't convert within window
            
            -- Never converted and mature enough
            ELSE 0  -- Negative: mature lead, never converted
        END as target_mql_43d,
        
        -- Additional metadata
        l.Company as company_name,
        l.LeadSource as lead_source,
        l.CreatedDate as lead_created_date
        
    FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
    WHERE l.stage_entered_contacting__c IS NOT NULL
        AND l.FA_CRD__c IS NOT NULL
        AND l.Company NOT LIKE '%Savvy%'  -- Exclude own company
)

SELECT * FROM contacted_leads
WHERE target_mql_43d IS NOT NULL;  -- Exclude right-censored
