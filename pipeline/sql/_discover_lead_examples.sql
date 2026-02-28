-- Tony Betancourt and Joshua Barone - get their lead fields
SELECT Id, Name, FA_CRD__c, Status, CreatedDate, LastModifiedDate
FROM `savvy-gtm-analytics.SavvyGTMData.Lead`
WHERE Id IN ('00QVS00000R6oze2AB', '00QVS00000A0J9l2AF') AND IsDeleted = false;
