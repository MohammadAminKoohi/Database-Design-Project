WITH branch_product_orders AS (
    SELECT
        oh.BranchID,
        oi.ProductID,
        SUM(oi.Quantity) AS TotalOrdered
    FROM Order_Header oh
    JOIN OrderItem oi ON oi.OrderID = oh.OrderID
    GROUP BY oh.BranchID, oi.ProductID
),
branch_totals AS (
    SELECT
        BranchID,
        SUM(TotalOrdered) AS BranchTotalOrdered
    FROM branch_product_orders
    GROUP BY BranchID
),
supplier_coverage AS (
    SELECT
        bso.BranchID,
        bso.SupplierID,
        SUM(bpo.TotalOrdered)   AS SupplierCoveredOrders,
        AVG(bso.LeadTime)       AS SupplierAvgLeadTime
    FROM BranchSupplyOffer bso
    JOIN branch_product_orders bpo
        ON bpo.BranchID = bso.BranchID
        AND bpo.ProductID = bso.ProductID
    GROUP BY bso.BranchID, bso.SupplierID
),
branch_avg_leadtime AS (
    SELECT
        BranchID,
        AVG(LeadTime) AS BranchAvgLeadTime
    FROM BranchSupplyOffer
    GROUP BY BranchID
)
SELECT
    b.BranchID,
    b.Name                              AS BranchName,
    s.SupplierID,
    s.Name                              AS SupplierName,
    sc.SupplierCoveredOrders,
    bt.BranchTotalOrdered,
    ROUND(sc.SupplierCoveredOrders * 100.0 / bt.BranchTotalOrdered, 2) AS CoveragePercent,
    ROUND(sc.SupplierAvgLeadTime, 2)    AS SupplierAvgLeadTime,
    ROUND(bal.BranchAvgLeadTime, 2)     AS BranchAvgLeadTime
FROM supplier_coverage sc
JOIN branch_totals bt
    ON bt.BranchID = sc.BranchID
JOIN branch_avg_leadtime bal
    ON bal.BranchID = sc.BranchID
JOIN Branch b
    ON b.BranchID = sc.BranchID
JOIN Supplier s
    ON s.SupplierID = sc.SupplierID
WHERE
    sc.SupplierCoveredOrders >= 0.5 * bt.BranchTotalOrdered
    AND sc.SupplierAvgLeadTime <= bal.BranchAvgLeadTime
ORDER BY
    b.BranchID,
    CoveragePercent DESC;