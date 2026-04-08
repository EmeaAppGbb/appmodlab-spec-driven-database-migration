CREATE TABLE CropManagement.CropTypes (
    CropTypeId INT PRIMARY KEY IDENTITY(1,1),
    Name NVARCHAR(100) NOT NULL,
    GrowingSeason NVARCHAR(50) NOT NULL,
    DaysToMaturity INT NOT NULL,
    MinTemperature DECIMAL(5,2),
    MaxTemperature DECIMAL(5,2),
    WaterRequirement NVARCHAR(20),
    CreatedDate DATETIME DEFAULT GETDATE(),
    ModifiedDate DATETIME DEFAULT GETDATE()
);

CREATE INDEX IX_CropTypes_Name ON CropManagement.CropTypes(Name);
CREATE INDEX IX_CropTypes_Season ON CropManagement.CropTypes(GrowingSeason);
