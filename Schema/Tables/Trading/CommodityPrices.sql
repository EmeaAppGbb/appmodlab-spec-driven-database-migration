CREATE TABLE Trading.CommodityPrices (
    PriceId INT PRIMARY KEY IDENTITY(1,1),
    CropTypeId INT NOT NULL,
    MarketDate DATE NOT NULL,
    PricePerBushel MONEY NOT NULL,
    MarketName NVARCHAR(100),
    CreatedDate DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Prices_CropType FOREIGN KEY (CropTypeId) REFERENCES CropManagement.CropTypes(CropTypeId)
);

CREATE INDEX IX_Prices_CropDate ON Trading.CommodityPrices(CropTypeId, MarketDate);
