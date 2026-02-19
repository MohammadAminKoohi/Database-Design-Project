CREATE OR REPLACE VIEW v_warehouse_unsent_product_orders AS
SELECT
    p.ProductID,
    p.Name AS ProductName,
    p.Category,
    p.SubCategory,
    SUM(oi.Quantity) AS TotalQuantity,
    COUNT(DISTINCT oi.OrderID) AS OrderCount
FROM OrderItem oi
JOIN Product p ON oi.ProductID = p.ProductID
WHERE oi.ItemStatus IN ('awaiting payment', 'item procurement')
GROUP BY p.ProductID, p.Name, p.Category, p.SubCategory
ORDER BY TotalQuantity DESC;

CREATE MATERIALIZED VIEW mv_daily_sales_profit AS
SELECT
    DATE(oh.OrderDate) AS sale_date,
    SUM(oh.TotalAmount) AS total_sales,
    SUM(oh.TotalAmount) - SUM(
        oi.Quantity * COALESCE(
            (SELECT MIN(bso.SupplyPrice)
             FROM BranchSupplyOffer bso
             WHERE bso.BranchID = oh.BranchID
               AND bso.ProductID = oi.ProductID),
            0
        )
    ) AS total_profit
FROM Order_Header oh
JOIN OrderItem oi ON oh.OrderID = oi.OrderID
GROUP BY DATE(oh.OrderDate)
ORDER BY sale_date DESC;

-- Index for efficient refresh and query
CREATE UNIQUE INDEX idx_mv_daily_sales_profit_date ON mv_daily_sales_profit (sale_date);

CREATE OR REPLACE VIEW v_branch_manager_customers AS
SELECT DISTINCT
    b.BranchID,
    b.Name AS BranchName,
    m.ManagerID,
    m.Name AS ManagerName,
    c.CustomerID,
    c.Name AS CustomerName,
    c.Phone,
    c.Email,
    c.Age,
    c.Gender,
    c.IncomeLevel,
    c.Nature,
    c.Tier
FROM Branch b
JOIN Manager m ON b.ManagerID = m.ManagerID
JOIN Order_Header oh ON oh.BranchID = b.BranchID
JOIN Customer c ON oh.CustomerID = c.CustomerID
ORDER BY b.BranchID, c.CustomerID;

CREATE OR REPLACE VIEW v_marketing_customer_loyalty AS
SELECT
    c.CustomerID,
    c.Name AS CustomerName,
    c.Email,
    COALESCE(SUM(oh.TotalAmount), 0) AS total_purchase_amount,
    c.LoyaltyPoints AS loyalty_points,
    c.Tier AS membership_tier
FROM Customer c
LEFT JOIN Order_Header oh ON c.CustomerID = oh.CustomerID
GROUP BY c.CustomerID, c.Name, c.Email, c.LoyaltyPoints, c.Tier
ORDER BY total_purchase_amount DESC;

CREATE OR REPLACE VIEW v_support_pending_returns AS
SELECT
    rr.ReturnID,
    rr.OrderID,
    rr.ProductID,
    p.Name AS ProductName,
    rr.RequestDate,
    rr.Reason,
    oi.Quantity,
    oi.CalculatedItemPrice,
    oi.ItemStatus,
    oh.OrderDate,
    oh.CustomerID
FROM ReturnRequest rr
JOIN OrderItem oi ON rr.OrderID = oi.OrderID AND rr.ProductID = oi.ProductID
JOIN Product p ON rr.ProductID = p.ProductID
JOIN Order_Header oh ON rr.OrderID = oh.OrderID
WHERE rr.ReviewResult IS NULL
ORDER BY rr.RequestDate;
