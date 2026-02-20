DEALLOCATE favorite_product_in_time;

PREPARE favorite_product_in_time AS
SELECT
    p.Name,
    AVG(pr.Score) AS avg_score
FROM OrderItem oi
JOIN Order_Header oh ON oi.OrderID = oh.OrderID
JOIN Product p ON oi.ProductID = p.ProductID
JOIN ProductReview pr ON pr.ProductID = p.ProductID
WHERE oh.OrderDate BETWEEN $1 AND $2
GROUP BY p.ProductID, p.Name
ORDER BY avg_score DESC NULLS LAST;

EXECUTE favorite_product_in_time('2020-01-01', '2025-01-01');

