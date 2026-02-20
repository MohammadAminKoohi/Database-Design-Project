deallocate category_popularity;

PREPARE category_popularity AS
SELECT
    p.SubCategory,
    p.Name                              AS ProductName,
    COUNT(pr.Score)                     AS ReviewCount,
    ROUND(AVG(pr.Score), 2)             AS AvgRating
FROM Product p
LEFT JOIN ProductReview pr ON pr.ProductID = p.ProductID
WHERE p.Category = $1
GROUP BY
    p.SubCategory,
    p.ProductID,
    p.Name
ORDER BY
    AvgRating DESC NULLS LAST,
    ReviewCount DESC;

EXECUTE category_popularity('Electronics');

