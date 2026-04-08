CREATE PROCEDURE Settlement.sp_CalculateMemberPayment
    @MemberId INT,
    @SettlementYear INT,
    @TotalPayment MONEY OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalYield DECIMAL(12,2);
    DECLARE @AverageGrade DECIMAL(5,2);
    DECLARE @QualityMultiplier DECIMAL(5,3);
    
    -- Calculate total yield for member in settlement year
    SELECT @TotalYield = SUM(h.YieldBushels)
    FROM CropManagement.Harvests h
    INNER JOIN CropManagement.Fields f ON h.FieldId = f.FieldId
    WHERE f.MemberId = @MemberId
        AND YEAR(h.HarvestDate) = @SettlementYear;
    
    -- Calculate average grade
    SELECT @AverageGrade = AVG(CAST(h.GradeCode AS DECIMAL(5,2)))
    FROM CropManagement.Harvests h
    INNER JOIN CropManagement.Fields f ON h.FieldId = f.FieldId
    WHERE f.MemberId = @MemberId
        AND YEAR(h.HarvestDate) = @SettlementYear;
    
    -- Quality multiplier based on grade
    SET @QualityMultiplier = CASE 
        WHEN @AverageGrade >= 90 THEN 1.15
        WHEN @AverageGrade >= 80 THEN 1.10
        WHEN @AverageGrade >= 70 THEN 1.05
        ELSE 1.00
    END;
    
    -- Calculate payment with quality bonus
    SELECT @TotalPayment = @TotalYield * cp.PricePerBushel * @QualityMultiplier
    FROM Trading.CommodityPrices cp
    WHERE cp.MarketDate = (SELECT MAX(MarketDate) FROM Trading.CommodityPrices WHERE YEAR(MarketDate) = @SettlementYear)
        AND cp.CropTypeId = (
            SELECT TOP 1 h.CropTypeId
            FROM CropManagement.Harvests h
            INNER JOIN CropManagement.Fields f ON h.FieldId = f.FieldId
            WHERE f.MemberId = @MemberId
            GROUP BY h.CropTypeId
            ORDER BY SUM(h.YieldBushels) DESC
        );
    
    RETURN 0;
END
GO
