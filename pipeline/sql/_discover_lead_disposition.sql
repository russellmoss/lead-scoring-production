SELECT Disposition__c, COUNT(*) as cnt 
FROM `savvy-gtm-analytics.SavvyGTMData.Lead` 
WHERE IsDeleted = false 
GROUP BY Disposition__c 
ORDER BY cnt DESC;
