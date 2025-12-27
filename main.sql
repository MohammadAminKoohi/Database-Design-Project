-- 1. MANAGER
CREATE TABLE Manager (
    ManagerID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL
);

-- 2. BRANCH (Dependent on Manager)
CREATE TABLE Branch (
    BranchID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Address VARCHAR(500),
    Phone VARCHAR(50),
    SalesVolume DECIMAL(15, 2),
    ManagerID INT NOT NULL,
    CONSTRAINT FK_Branch_Manager FOREIGN KEY (ManagerID) REFERENCES Manager(ManagerID)
);

-- 3. CUSTOMER
CREATE TABLE Customer (
    CustomerID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Phone VARCHAR(50),
    Email VARCHAR(255),
    Age INT,
    Gender CHAR(1) CHECK (Gender IN ('M', 'F')),
    IncomeLevel VARCHAR(50),
    Nature VARCHAR(50) CHECK (Nature IN ('consumer', 'corporate')), -- consumer or person responsible for company's purchases
    Tier VARCHAR(50) CHECK (Tier IN ('new', 'regular', 'special')), -- new, regular, or special
    TaxAmount DECIMAL(10, 2) DEFAULT 0.10, -- <<tax_req>> VAT rate (10% default, can be 0 for exempt)
    LoyaltyPoints INT DEFAULT 0, -- <<derived>> Every 100 Toman = 1 point (last 3 months)
    CreditLimit DECIMAL(15, 2), -- <<derived>> 20 × LoyaltyPoints
    Debt DECIMAL(15, 2) DEFAULT 0 -- <<derived>>
);

-- 4. WALLET (1:1 with Customer)
CREATE TABLE Wallet (
    CustomerID INT PRIMARY KEY, -- Serves as PK and FK
    Balance DECIMAL(15, 2) DEFAULT 0.00,
    CONSTRAINT FK_Wallet_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- 5. WALLET_TRANSACTION (Dependent on Wallet)
CREATE TABLE WalletTransaction (
    TransactionID INT PRIMARY KEY,
    CustomerID INT NOT NULL, -- Links to Wallet
    Type VARCHAR(50) CHECK (Type IN ('Deposit', 'Payment')), -- Deposit or Payment
    Amount DECIMAL(15, 2),
    Date DATETIME NOT NULL,
    CONSTRAINT FK_WTrans_Wallet FOREIGN KEY (CustomerID) REFERENCES Wallet(CustomerID)
);

-- 6. PRODUCT
CREATE TABLE Product (
    ProductID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Category VARCHAR(100),
    SubCategory VARCHAR(100),
    BaseInfo TEXT,
    TaxAmount DECIMAL(10, 2) DEFAULT 0.10 -- <<tax_req>> VAT rate (10% default, can be 0 for exempt)
);

-- 7. SUPPLIER
CREATE TABLE Supplier (
    SupplierID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Phone VARCHAR(50),
    Address VARCHAR(500)
);

-- 8. WAREHOUSE (Dependent on Branch)
CREATE TABLE Warehouse (
    WarehouseID INT PRIMARY KEY,
    Name VARCHAR(255),
    Address VARCHAR(500),
    BranchID INT NOT NULL, -- OWNS relationship
    CONSTRAINT FK_Warehouse_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- 9. ORDER (Dependent on Customer and Branch)
CREATE TABLE Order_Header (
    OrderID INT PRIMARY KEY,
    OrderDate DATETIME NOT NULL,
    Priority VARCHAR(50) DEFAULT 'low' CHECK (Priority IN ('lowest', 'low', 'medium', 'high', 'highest')), -- 5 levels from lowest to highest, default low
    TotalAmount DECIMAL(15, 2), -- <<derived>> shipping cost + (final price × quantity) + VAT
    PaymentMethod VARCHAR(50) CHECK (PaymentMethod IN ('credit card', 'debit card', 'cash', 'wallet', 'BNPL')), -- credit card, debit card, cash, wallet, or BNPL
    LoyaltyDiscount DECIMAL(10, 2) DEFAULT 0, -- <<loyalty_req>> Bronze: 0%, Silver: 5%, Gold: 10%
    CustomerID INT NOT NULL, -- PLACES relationship
    BranchID INT NOT NULL,   -- PROCESSED_AT relationship
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Order_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- 10. SHIPMENT (1:1 with Order)
CREATE TABLE Shipment (
    ShipmentID INT PRIMARY KEY,
    TrackingCode VARCHAR(100),
    ShipDate DATETIME,
    RecipientAddress VARCHAR(500),
    City VARCHAR(100),
    ZipCode VARCHAR(20),
    Type VARCHAR(50) DEFAULT 'standard' CHECK (Type IN ('standard', 'custom', 'same-day')), -- standard (default), custom, or same-day
    TransportMethod VARCHAR(100) CHECK (TransportMethod IN ('ground', 'airmail', 'air freight')), -- ground or air (airmail or air freight)
    Cost DECIMAL(10, 2),
    PackType VARCHAR(50) CHECK (PackType IN ('box', 'envelope')), -- box or envelope
    PackSize VARCHAR(50), -- box: 3 sizes (small, medium, large); envelope: 4 types (2 sizes × 2 types: regular, bubble)
    OrderID INT NOT NULL UNIQUE, -- SHIPPED_VIA relationship (1:1 ensures UNIQUE)
    CONSTRAINT FK_Shipment_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID),
    CONSTRAINT CHK_PackSize CHECK (
        (PackType = 'box' AND PackSize IN ('small', 'medium', 'large')) OR
        (PackType = 'envelope' AND PackSize IN ('small-regular', 'small-bubble', 'large-regular', 'large-bubble')) OR
        PackType IS NULL
    )
);

-- 11. REPAYMENT_HISTORY (Weak Entity on Order)
CREATE TABLE RepaymentHistory (
    OrderID INT NOT NULL,
    PaymentDate DATETIME NOT NULL,
    Amount DECIMAL(15, 2),
    PaymentMethod VARCHAR(50) CHECK (PaymentMethod IN ('credit card', 'debit card', 'cash', 'wallet')), -- credit card, debit card, cash, or wallet
    PRIMARY KEY (OrderID, PaymentDate), -- Composite PK
    CONSTRAINT FK_Repayment_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID)
);

-- 12. ORDER_ITEM (Associative Entity: CONTAINS)
CREATE TABLE OrderItem (
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    CalculatedItemPrice DECIMAL(15, 2), -- <<derived>>
    ItemStatus VARCHAR(50) CHECK (ItemStatus IN ('awaiting payment', 'item procurement', 'shipped', 'received', 'unknown', 'Pending Return Review', 'Return Approved', 'Return Rejected')), -- <<return_req>> Original statuses + return statuses
    PRIMARY KEY (OrderID, ProductID),
    CONSTRAINT FK_Item_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID),
    CONSTRAINT FK_Item_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 13. RETURN_REQUEST (Linked to CONTAINS/OrderItem)
CREATE TABLE ReturnRequest (
    ReturnID INT PRIMARY KEY,
    RequestDate DATETIME NOT NULL,
    Reason TEXT,
    ReviewResult VARCHAR(100) CHECK (ReviewResult IN ('Approved', 'Rejected', NULL)), -- Approved or Rejected
    DecisionDate DATETIME,
    -- Foreign Key points to the specific line item in the order
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT FK_Return_OrderItem FOREIGN KEY (OrderID, ProductID) REFERENCES OrderItem(OrderID, ProductID)
);

-- 14. PRODUCT_REVIEW (Associative Entity: REVIEWS)
CREATE TABLE ProductReview (
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    Score INT CHECK (Score >= 1 AND Score <= 5), -- Numerical feedback between 1 and 5
    Comment TEXT, -- Text feedback (new requirement)
    ImageData TEXT, -- Images stored as strings directly in database (base64 encoded)
    IsPublic BOOLEAN DEFAULT TRUE, -- If buyer agrees, feedback is published publicly
    PRIMARY KEY (CustomerID, ProductID), -- Assuming 1 review per user per product
    CONSTRAINT FK_Review_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Review_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 15. WAREHOUSE_INVENTORY (Associative Entity: STORES)
CREATE TABLE WarehouseInventory (
    WarehouseID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT DEFAULT 0,
    PRIMARY KEY (WarehouseID, ProductID),
    CONSTRAINT FK_Inv_Warehouse FOREIGN KEY (WarehouseID) REFERENCES Warehouse(WarehouseID),
    CONSTRAINT FK_Inv_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 16. BRANCH_SUPPLY_OFFER (Ternary Relationship: OFFERS)
-- Connects Branch, Supplier, and Product
CREATE TABLE BranchSupplyOffer (
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    SupplierID INT NOT NULL,
    SellingPrice DECIMAL(15, 2),
    SupplyPrice DECIMAL(15, 2),
    LeadTime INT, -- e.g., in days
    Discount DECIMAL(5, 2),
    IsAvailable BOOLEAN DEFAULT TRUE,
    TechnicalSpecs_JSON TEXT, -- Stores JSON data
    PRIMARY KEY (BranchID, ProductID, SupplierID),
    CONSTRAINT FK_Offer_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CONSTRAINT FK_Offer_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    CONSTRAINT FK_Offer_Supplier FOREIGN KEY (SupplierID) REFERENCES Supplier(SupplierID)
);