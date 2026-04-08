CREATE TRIGGER tr_AuditHarvestChanges
ON CropManagement.Harvests
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Log all changes to harvests for regulatory compliance
    IF EXISTS (SELECT * FROM inserted)
    BEGIN
        INSERT INTO Audit.HarvestAuditLog (HarvestId, ChangeType, ChangedBy, ChangeDate, OldValue, NewValue)
        SELECT 
            COALESCE(i.HarvestId, d.HarvestId),
            CASE 
                WHEN i.HarvestId IS NOT NULL AND d.HarvestId IS NULL THEN 'INSERT'
                WHEN i.HarvestId IS NOT NULL AND d.HarvestId IS NOT NULL THEN 'UPDATE'
                ELSE 'DELETE'
            END,
            SUSER_SNAME(),
            GETDATE(),
            (SELECT * FROM deleted d2 WHERE d2.HarvestId = COALESCE(i.HarvestId, d.HarvestId) FOR JSON AUTO),
            (SELECT * FROM inserted i2 WHERE i2.HarvestId = i.HarvestId FOR JSON AUTO)
        FROM inserted i
        FULL OUTER JOIN deleted d ON i.HarvestId = d.HarvestId;
    END
END
GO
