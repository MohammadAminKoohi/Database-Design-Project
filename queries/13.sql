DEALLOCATE get_attribute_values;

PREPARE get_attribute_values(text, text, text) AS
SELECT DISTINCT
    (BaseInfo::jsonb) ->> $1 AS attribute_value
FROM
    Product
WHERE
    Category = $2
    AND SubCategory = $3
    AND (BaseInfo::jsonb) ->> $1 IS NOT NULL;

EXECUTE get_attribute_values('camera', 'Electronics', 'Mobile Phones');