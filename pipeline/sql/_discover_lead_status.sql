-- Distinct Status and StageName (or similar) from Lead
SELECT Status, COUNT(*) as cnt FROM `savvy-gtm-analytics.SavvyGTMData.Lead` WHERE IsDeleted = false GROUP BY Status ORDER BY cnt DESC;
