-- Count recyclable candidates by Status with activity thresholds
-- Nurture: 300+ days no contact; Closed: 180+ days no contact
WITH lead_task_activity AS (
    SELECT t.WhoId as lead_id,
        MAX(GREATEST(
            COALESCE(DATE(t.ActivityDate), DATE('1900-01-01')),
            COALESCE(DATE(t.CompletedDateTime), DATE('1900-01-01')),
            COALESCE(DATE(t.CreatedDate), DATE('1900-01-01'))
        )) as last_activity_date
    FROM `savvy-gtm-analytics.SavvyGTMData.Task` t
    WHERE t.IsDeleted = false AND t.WhoId IS NOT NULL
      AND (t.Type IN ('Outgoing SMS', 'Incoming SMS') OR UPPER(t.Subject) LIKE '%SMS%' OR UPPER(t.Subject) LIKE '%TEXT%'
           OR t.TaskSubtype = 'Call' OR t.Type = 'Call' OR UPPER(t.Subject) LIKE '%CALL%' OR t.CallType IS NOT NULL)
    GROUP BY t.WhoId
)
SELECT 
  l.Status,
  COUNT(*) as total,
  COUNTIF(la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) >= 300) as no_contact_300_plus,
  COUNTIF(la.last_activity_date IS NULL OR DATE_DIFF(CURRENT_DATE(), la.last_activity_date, DAY) >= 180) as no_contact_180_plus
FROM `savvy-gtm-analytics.SavvyGTMData.Lead` l
LEFT JOIN lead_task_activity la ON l.Id = la.lead_id
WHERE l.IsDeleted = false AND l.FA_CRD__c IS NOT NULL
  AND (l.DoNotCall IS NULL OR l.DoNotCall = false)
  AND l.Status IN ('Nurture', 'Closed', 'New', 'Qualified')
GROUP BY l.Status
ORDER BY l.Status;
