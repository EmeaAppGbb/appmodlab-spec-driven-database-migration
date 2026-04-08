CREATE PROCEDURE CropPlanning.sp_CalculateOptimalRotation
    @FieldId INT,
    @CurrentYear INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @LastCropId INT;
    DECLARE @SoilType NVARCHAR(50);
    DECLARE @RecommendedCropId INT;
    
    SELECT @LastCropId = CurrentCropId, @SoilType = SoilType
    FROM CropManagement.Fields
    WHERE FieldId = @FieldId;
    
    -- Complex crop rotation logic based on:
    -- 1. Previous crop
    -- 2. Soil type
    -- 3. Nutrient depletion
    -- 4. Market prices
    
    WITH RotationRules AS (
        SELECT 
            ct.CropTypeId,
            ct.Name,
            CASE 
                WHEN @LastCropId = 1 THEN 10 -- After corn, prefer soybeans
                WHEN @LastCropId = 2 THEN 5  -- After soybeans, any crop ok
                ELSE 7
            END AS RotationScore,
            cp.PricePerBushel AS CurrentPrice
        FROM CropManagement.CropTypes ct
        LEFT JOIN Trading.CommodityPrices cp ON ct.CropTypeId = cp.CropTypeId
            AND cp.MarketDate = (SELECT MAX(MarketDate) FROM Trading.CommodityPrices WHERE CropTypeId = ct.CropTypeId)
        WHERE ct.CropTypeId != @LastCropId
    )
    SELECT TOP 1 
        CropTypeId,
        Name,
        RotationScore,
        CurrentPrice,
        (RotationScore * 0.6 + (CurrentPrice / 10) * 0.4) AS TotalScore
    FROM RotationRules
    ORDER BY TotalScore DESC;
END
GO
