-- Simple mock data for ProductReview Used for 2.sql query
INSERT INTO ProductReview (ProductID, CustomerID, Score, comment)
SELECT
    oi.ProductID,
    oh.CustomerID,
    -- Random score between 1-5
    (random() * 4 + 1)::INT AS Score,
    -- Simple comment based on score
    'Good product' AS comment
FROM OrderItem oi
JOIN Order_Header oh ON oi.OrderID = oh.OrderID
WHERE random() < 0.3  -- 30% of orders get reviews
LIMIT 500;

-- Verify the data
SELECT COUNT(*) FROM ProductReview;
