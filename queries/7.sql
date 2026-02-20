deallocate mutual_branch_customers;

PREPARE mutual_branch_customers AS

SELECT
    c.CustomerID,
    c.name AS customer_name,
    b1.name AS branch1_name,
    COUNT(DISTINCT CASE WHEN oh.BranchID = $1 THEN oh.OrderID END) AS orders_in_branch1,
    b2.name AS branch2_name,
    COUNT(DISTINCT CASE WHEN oh.BranchID = $2 THEN oh.OrderID END) AS orders_in_branch2,
    CASE
        WHEN COUNT(DISTINCT CASE WHEN oh.BranchID = $1 THEN oh.OrderID END) >=
             COUNT(DISTINCT CASE WHEN oh.BranchID = $2 THEN oh.OrderID END)
        THEN b1.name
        ELSE b2.name
    END AS preferred_branch
FROM Customer c
JOIN Order_Header oh ON c.CustomerID = oh.CustomerID
CROSS JOIN Branch b1
CROSS JOIN Branch b2
WHERE b1.BranchID = $1
  AND b2.BranchID = $2
  AND oh.BranchID IN ($1, $2)
  AND c.CustomerID IN (
      SELECT oh1.CustomerID FROM Order_Header oh1 WHERE oh1.BranchID = $1
      INTERSECT
      SELECT oh2.CustomerID FROM Order_Header oh2 WHERE oh2.BranchID = $2
  )
GROUP BY c.CustomerID, c.name, c.CustomerID, b1.name, b2.name
ORDER BY customer_name;


execute mutual_branch_customers(1 , 2);
