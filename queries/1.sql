deallocate subcategory_profit;


PREPARE subcategory_profit AS

SELECT
    p.SubCategory,
    SUM((bso.SellingPrice - bso.SupplyPrice) * oi.Quantity) /
        NULLIF(SUM(oi.Quantity), 0) AS weighted_avg_profit_margin
FROM OrderItem oi
JOIN Product p ON oi.ProductID = p.ProductID
JOIN Order_Header oh ON oi.OrderID = oh.OrderID
JOIN BranchSupplyOffer bso
    ON bso.ProductID = oi.ProductID AND bso.BranchID = oh.BranchID
WHERE p.Category = $1
GROUP BY p.SubCategory;

EXPLAIN ANALYZE
execute subcategory_profit('Clothing');
