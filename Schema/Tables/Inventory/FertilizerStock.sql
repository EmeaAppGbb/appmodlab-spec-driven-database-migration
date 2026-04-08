CREATE TABLE Inventory.FertilizerStock (
    StockId INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    ManufacturerName NVARCHAR(100),
    QuantityOnHand DECIMAL(12,2) NOT NULL,
    Unit NVARCHAR(20) NOT NULL,
    CostPerUnit MONEY NOT NULL,
    ReorderLevel DECIMAL(12,2),
    LastRestockDate DATE,
    ExpirationDate DATE,
    CreatedDate DATETIME DEFAULT GETDATE()
);

CREATE INDEX IX_Fertilizer_Product ON Inventory.FertilizerStock(ProductName);
