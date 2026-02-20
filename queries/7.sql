-- Input: :branch1_id and :branch2_id
WITH orders_per_branch AS (
    SELECT
        c.CustomerID,
        c.Name AS CustomerName,
        oh.BranchID,
        b.Name AS BranchName,
        COUNT(oh.OrderID) AS OrderCount
    FROM Order_Header oh
    JOIN Customer c ON c.CustomerID = oh.CustomerID
    JOIN Branch b ON b.BranchID = oh.BranchID
    WHERE oh.BranchID IN (:branch1_id, :branch2_id)
    GROUP BY c.CustomerID, c.Name, oh.BranchID, b.Name
),
customers_in_both AS (
    SELECT CustomerID
    FROM orders_per_branch
    GROUP BY CustomerID
    HAVING COUNT(DISTINCT BranchID) = 2
),
ranked AS (
    SELECT
        opb.CustomerID,
        opb.CustomerName,
        opb.BranchID,
        opb.BranchName,
        opb.OrderCount,
        RANK() OVER (PARTITION BY opb.CustomerID ORDER BY opb.OrderCount DESC) AS rnk
    FROM orders_per_branch opb
    WHERE opb.CustomerID IN (SELECT CustomerID FROM customers_in_both)
)
SELECT
    r.CustomerName,
    MAX(CASE WHEN r.BranchID = :branch1_id THEN r.OrderCount END) AS OrdersInBranch1,
    MAX(CASE WHEN r.BranchID = :branch2_id THEN r.OrderCount END) AS OrdersInBranch2,
    MAX(CASE WHEN r.rnk = 1 THEN r.BranchName END) AS MostOrderedBranch
FROM ranked r
GROUP BY r.CustomerID, r.CustomerName
ORDER BY r.CustomerName;