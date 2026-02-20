DEALLOCATE product_dependency;

prepare product_dependency as
SELECT DISTINCT
    p2.Category AS associated_category
FROM OrderItem oi1
JOIN Product p1 ON oi1.ProductID = p1.ProductID AND p1.Category = $1
JOIN OrderItem oi2 ON oi1.OrderID = oi2.OrderID AND oi2.ProductID <> oi1.ProductID
JOIN Product p2 ON oi2.ProductID = p2.ProductID AND p2.Category <> $1
GROUP BY p2.Category
HAVING COUNT(DISTINCT oi1.OrderID) >= $2;

EXPLAIN ANALYZE
execute product_dependency('Clothing', 2);