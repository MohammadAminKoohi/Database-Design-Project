deallocate payed_tax;

PREPARE payed_tax AS

SELECT
    oh.CustomerID,
    SUM(oh.TotalAmount * c.TaxAmount) AS total_tax_paid
FROM Order_Header oh
JOIN Customer c ON oh.CustomerID = c.CustomerID
WHERE oh.CustomerID = $1
GROUP BY oh.CustomerID;

execute payed_tax(2)