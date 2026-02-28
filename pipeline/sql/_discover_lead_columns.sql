-- Lead table: list columns that might be Stage/Status
SELECT column_name, data_type 
FROM `savvy-gtm-analytics.SavvyGTMData.INFORMATION_SCHEMA.COLUMNS` 
WHERE table_name = 'Lead' 
AND (LOWER(column_name) LIKE '%stage%' OR LOWER(column_name) LIKE '%status%' OR LOWER(column_name) LIKE '%name%')
ORDER BY ordinal_position;
