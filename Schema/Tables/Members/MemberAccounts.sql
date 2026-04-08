CREATE TABLE Members.MemberAccounts (
    MemberId INT PRIMARY KEY IDENTITY(1,1),
    MemberNumber NVARCHAR(20) UNIQUE NOT NULL,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100),
    PhoneNumber NVARCHAR(20),
    Address NVARCHAR(200),
    City NVARCHAR(50),
    State NVARCHAR(2),
    ZipCode NVARCHAR(10),
    MembershipDate DATE NOT NULL,
    Status NVARCHAR(20) DEFAULT 'Active',
    CreatedDate DATETIME DEFAULT GETDATE(),
    ModifiedDate DATETIME DEFAULT GETDATE()
);

CREATE INDEX IX_Members_Number ON Members.MemberAccounts(MemberNumber);
CREATE INDEX IX_Members_Name ON Members.MemberAccounts(LastName, FirstName);
