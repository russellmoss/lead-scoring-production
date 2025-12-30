-- File: v4/sql/v4.1/create_firm_rep_type_features.sql
-- Purpose: Extract firm type and rep type features for V4.1
-- Source: Analysis of 35,361 contacted leads showing Independent RIA + IA rep type converts at 1.33x baseline

CREATE OR REPLACE TABLE `savvy-gtm-analytics.ml_features.firm_rep_type_features_v41` AS

SELECT 
    CAST(RIA_CONTACT_CRD_ID AS INT64) as advisor_crd,
    
    -- Independent RIA flag (positive signal: 1.33x lift)
    CASE 
        WHEN PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' 
        THEN 1 ELSE 0 
    END as is_independent_ria,
    
    -- Pure IA rep type - no broker-dealer registration (positive signal)
    CASE 
        WHEN REP_TYPE = 'IA' THEN 1 ELSE 0 
    END as is_ia_rep_type,
    
    -- Dual registered - has both IA and BD (NEGATIVE signal: 0.86-0.90x lift)
    CASE 
        WHEN REP_TYPE = 'DR' THEN 1 ELSE 0 
    END as is_dual_registered,
    
    -- Interaction: Independent RIA + IA rep type (strongest positive signal)
    CASE 
        WHEN PRIMARY_FIRM_CLASSIFICATION LIKE '%Independent RIA%' 
         AND REP_TYPE = 'IA'
        THEN 1 ELSE 0 
    END as independent_ria_x_ia_rep

FROM `savvy-gtm-analytics.FinTrx_data_CA.ria_contacts_current`
WHERE RIA_CONTACT_CRD_ID IS NOT NULL
  AND PRODUCING_ADVISOR = TRUE;  -- Only producing advisors

