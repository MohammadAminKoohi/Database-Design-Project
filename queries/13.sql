DEALLOCATE tech_specs;

PREPARE tech_specs AS
SELECT DISTINCT
    p.Category,
    p.SubCategory,
    $3 AS Attribute
from Product as p
WHERE TRIM(p.Category) = $1
  AND TRIM(p.SubCategory) = $2
ORDER BY Attribute;

EXECUTE tech_specs('Electronics', 'Mobile Phones', 'camera');