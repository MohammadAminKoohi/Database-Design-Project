-- PostgreSQL-compatible schema (DATETIME -> TIMESTAMP)
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
    Nature VARCHAR(50) CHECK (Nature IN ('consumer', 'corporate')),
    Tier VARCHAR(50) CHECK (Tier IN ('new', 'regular', 'special')),
    TaxAmount DECIMAL(10, 2) DEFAULT 0.10,
    LoyaltyPoints INT DEFAULT 0,
    CreditLimit DECIMAL(15, 2),
    Debt DECIMAL(15, 2) DEFAULT 0
);

-- 4. WALLET (1:1 with Customer)
CREATE TABLE Wallet (
    CustomerID INT PRIMARY KEY,
    Balance DECIMAL(15, 2) DEFAULT 0.00,
    CONSTRAINT FK_Wallet_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- 5. WALLET_TRANSACTION
CREATE TABLE WalletTransaction (
    TransactionID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    Type VARCHAR(50) CHECK (Type IN ('Deposit', 'Payment')),
    Amount DECIMAL(15, 2),
    Date TIMESTAMP NOT NULL,
    CONSTRAINT FK_WTrans_Wallet FOREIGN KEY (CustomerID) REFERENCES Wallet(CustomerID)
);

-- 6. PRODUCT
CREATE TABLE Product (
    ProductID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Category VARCHAR(100),
    SubCategory VARCHAR(100),
    BaseInfo TEXT,
    TaxAmount DECIMAL(10, 2) DEFAULT 0.10
);

-- 7. SUPPLIER
CREATE TABLE Supplier (
    SupplierID INT PRIMARY KEY,
    Name VARCHAR(255) NOT NULL,
    Phone VARCHAR(50),
    Address VARCHAR(500)
);

-- 8. WAREHOUSE
CREATE TABLE Warehouse (
    WarehouseID INT PRIMARY KEY,
    Name VARCHAR(255),
    Address VARCHAR(500),
    BranchID INT NOT NULL,
    CONSTRAINT FK_Warehouse_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- 9. ORDER_HEADER
CREATE TABLE Order_Header (
    OrderID INT PRIMARY KEY,
    OrderDate TIMESTAMP NOT NULL,
    Priority VARCHAR(50) DEFAULT 'low' CHECK (Priority IN ('lowest', 'low', 'medium', 'high', 'highest')),
    TotalAmount DECIMAL(15, 2),
    PaymentMethod VARCHAR(50) CHECK (PaymentMethod IN ('credit card', 'debit card', 'cash', 'wallet', 'BNPL')),
    LoyaltyDiscount DECIMAL(10, 2) DEFAULT 0,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Order_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID)
);

-- 10. SHIPMENT
CREATE TABLE Shipment (
    ShipmentID INT PRIMARY KEY,
    TrackingCode VARCHAR(100),
    ShipDate TIMESTAMP,
    RecipientAddress VARCHAR(500),
    City VARCHAR(100),
    ZipCode VARCHAR(20),
    Type VARCHAR(50) DEFAULT 'standard' CHECK (Type IN ('standard', 'custom', 'same-day')),
    TransportMethod VARCHAR(100) CHECK (TransportMethod IN ('ground', 'airmail', 'air freight')),
    Cost DECIMAL(10, 2),
    PackType VARCHAR(50) CHECK (PackType IN ('box', 'envelope')),
    PackSize VARCHAR(50),
    OrderID INT NOT NULL UNIQUE,
    CONSTRAINT FK_Shipment_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID),
    CONSTRAINT CHK_PackSize CHECK (
        (PackType = 'box' AND PackSize IN ('small', 'medium', 'large')) OR
        (PackType = 'envelope' AND PackSize IN ('small-regular', 'small-bubble', 'large-regular', 'large-bubble')) OR
        PackType IS NULL
    )
);

-- 11. REPAYMENT_HISTORY
CREATE TABLE RepaymentHistory (
    OrderID INT NOT NULL,
    PaymentDate TIMESTAMP NOT NULL,
    Amount DECIMAL(15, 2),
    PaymentMethod VARCHAR(50) CHECK (PaymentMethod IN ('credit card', 'debit card', 'cash', 'wallet')),
    PRIMARY KEY (OrderID, PaymentDate),
    CONSTRAINT FK_Repayment_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID)
);

-- 12. ORDER_ITEM
CREATE TABLE OrderItem (
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    CalculatedItemPrice DECIMAL(15, 2),
    ItemStatus VARCHAR(50) CHECK (ItemStatus IN ('awaiting payment', 'item procurement', 'shipped', 'received', 'unknown', 'Pending Return Review', 'Return Approved', 'Return Rejected')),
    PRIMARY KEY (OrderID, ProductID),
    CONSTRAINT FK_Item_Order FOREIGN KEY (OrderID) REFERENCES Order_Header(OrderID),
    CONSTRAINT FK_Item_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 13. RETURN_REQUEST
CREATE TABLE ReturnRequest (
    ReturnID INT PRIMARY KEY,
    RequestDate TIMESTAMP NOT NULL,
    Reason TEXT,
    ReviewResult VARCHAR(100) CHECK (ReviewResult IS NULL OR ReviewResult IN ('Approved', 'Rejected')),
    DecisionDate TIMESTAMP,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT FK_Return_OrderItem FOREIGN KEY (OrderID, ProductID) REFERENCES OrderItem(OrderID, ProductID)
);

-- 14. PRODUCT_REVIEW
CREATE TABLE ProductReview (
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    Score INT CHECK (Score >= 1 AND Score <= 5),
    Comment TEXT,
    ImageData TEXT,
    IsPublic BOOLEAN DEFAULT TRUE,
    PRIMARY KEY (CustomerID, ProductID),
    CONSTRAINT FK_Review_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Review_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 15. WAREHOUSE_INVENTORY
CREATE TABLE WarehouseInventory (
    WarehouseID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT DEFAULT 0,
    PRIMARY KEY (WarehouseID, ProductID),
    CONSTRAINT FK_Inv_Warehouse FOREIGN KEY (WarehouseID) REFERENCES Warehouse(WarehouseID),
    CONSTRAINT FK_Inv_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- 16. BRANCH_SUPPLY_OFFER
CREATE TABLE BranchSupplyOffer (
    BranchID INT NOT NULL,
    ProductID INT NOT NULL,
    SupplierID INT NOT NULL,
    SellingPrice DECIMAL(15, 2),
    SupplyPrice DECIMAL(15, 2),
    LeadTime INT,
    Discount DECIMAL(5, 2),
    IsAvailable BOOLEAN DEFAULT TRUE,
    TechnicalSpecs_JSON TEXT,
    PRIMARY KEY (BranchID, ProductID, SupplierID),
    CONSTRAINT FK_Offer_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID),
    CONSTRAINT FK_Offer_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    CONSTRAINT FK_Offer_Supplier FOREIGN KEY (SupplierID) REFERENCES Supplier(SupplierID)
);
