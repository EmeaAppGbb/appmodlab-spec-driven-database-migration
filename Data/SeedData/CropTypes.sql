-- Seed data for CropTypes
INSERT INTO CropManagement.CropTypes (Name, GrowingSeason, DaysToMaturity, MinTemperature, MaxTemperature, WaterRequirement)
VALUES 
    ('Corn', 'Spring/Summer', 120, 10.0, 30.0, 'High'),
    ('Soybeans', 'Spring/Summer', 100, 15.0, 28.0, 'Medium'),
    ('Wheat', 'Fall/Winter', 180, 0.0, 25.0, 'Low'),
    ('Barley', 'Spring', 90, 5.0, 22.0, 'Medium'),
    ('Oats', 'Spring', 80, 7.0, 20.0, 'Medium');
