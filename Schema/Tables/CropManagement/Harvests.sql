CREATE TABLE CropManagement.Harvests (
    HarvestId INT PRIMARY KEY IDENTITY(1,1),
    FieldId INT NOT NULL,
    CropTypeId INT NOT NULL,
    HarvestDate DATE NOT NULL,
    YieldBushels AS (dbo.fn_CalculateYieldBushels(Quantity, UnitType)) PERSISTED,
    Quantity DECIMAL(12,2) NOT NULL,
    UnitType NVARCHAR(20) NOT NULL,
    MoistureContent DECIMAL(5,2),
    GradeCode NVARCHAR(10),
    CreatedDate DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Harvests_Field FOREIGN KEY (FieldId) REFERENCES CropManagement.Fields(FieldId),
    CONSTRAINT FK_Harvests_CropType FOREIGN KEY (CropTypeId) REFERENCES CropManagement.CropTypes(CropTypeId)
);

CREATE INDEX IX_Harvests_Field ON CropManagement.Harvests(FieldId);
CREATE INDEX IX_Harvests_Date ON CropManagement.Harvests(HarvestDate);
