DEALLOCATE new_valuable_customers;

PREPARE new_valuable_customers AS
SELECT
    c.Name,
    c.Phone
FROM Customer c
JOIN Order_Header oh ON oh.CustomerID = c.CustomerID
WHERE c.Tier = 'new'
  AND oh.OrderDate >= $1::date - INTERVAL '1 month'
  AND oh.OrderDate <= $1::date
GROUP BY c.CustomerID, c.Name, c.Phone
HAVING COUNT(oh.OrderID) > $2
   AND SUM(oh.TotalAmount) > $3;

EXECUTE new_valuable_customers('2021-02-01', 1, 1);
