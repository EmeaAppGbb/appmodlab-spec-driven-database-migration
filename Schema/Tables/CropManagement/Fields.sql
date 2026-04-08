CREATE TABLE CropManagement.Fields (
    FieldId INT PRIMARY KEY IDENTITY(1,1),
    MemberId INT NOT NULL,
    FieldName NVARCHAR(100) NOT NULL,
    Acreage DECIMAL(10,2) NOT NULL,
    SoilType NVARCHAR(50),
    IrrigationType NVARCHAR(50),
    GPSBoundary GEOGRAPHY,
    CurrentCropId INT,
    CreatedDate DATETIME DEFAULT GETDATE(),
    ModifiedDate DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Fields_Member FOREIGN KEY (MemberId) REFERENCES Members.MemberAccounts(MemberId),
    CONSTRAINT FK_Fields_CurrentCrop FOREIGN KEY (CurrentCropId) REFERENCES CropManagement.CropTypes(CropTypeId)
);

CREATE INDEX IX_Fields_Member ON CropManagement.Fields(MemberId);
CREATE INDEX IX_Fields_CurrentCrop ON CropManagement.Fields(CurrentCropId);
