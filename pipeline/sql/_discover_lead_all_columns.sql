-- All Lead columns (to find StageName or equivalent)
SELECT column_name FROM `savvy-gtm-analytics.SavvyGTMData.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'Lead' ORDER BY ordinal_position;
