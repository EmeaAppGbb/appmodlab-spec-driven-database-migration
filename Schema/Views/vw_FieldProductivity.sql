CREATE VIEW CropManagement.vw_FieldProductivity
AS
SELECT 
    f.FieldId,
    f.FieldName,
    m.MemberNumber,
    m.FirstName + ' ' + m.LastName AS MemberName,
    f.Acreage,
    ct.Name AS CurrentCrop,
    SUM(h.YieldBushels) AS TotalYield,
    SUM(h.YieldBushels) / f.Acreage AS YieldPerAcre,
    COUNT(h.HarvestId) AS HarvestCount,
    MAX(h.HarvestDate) AS LastHarvestDate
FROM CropManagement.Fields f
INNER JOIN Members.MemberAccounts m ON f.MemberId = m.MemberId
LEFT JOIN CropManagement.CropTypes ct ON f.CurrentCropId = ct.CropTypeId
LEFT JOIN CropManagement.Harvests h ON f.FieldId = h.FieldId
GROUP BY f.FieldId, f.FieldName, m.MemberNumber, m.FirstName, m.LastName, f.Acreage, ct.Name;
GO
