CREATE FUNCTION dbo.fn_CalculateYieldBushels
(
    @Quantity DECIMAL(12,2),
    @UnitType NVARCHAR(20)
)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @Bushels DECIMAL(12,2);
    
    -- Convert various units to bushels
    SET @Bushels = CASE @UnitType
        WHEN 'bushels' THEN @Quantity
        WHEN 'tonnes' THEN @Quantity * 36.7437  -- 1 tonne = 36.7437 bushels (wheat)
        WHEN 'hundredweight' THEN @Quantity * 1.667  -- 1 cwt = 1.667 bushels
        WHEN 'kilograms' THEN @Quantity * 0.0367437
        ELSE @Quantity  -- Default to bushels if unknown
    END;
    
    RETURN @Bushels;
END
GO
