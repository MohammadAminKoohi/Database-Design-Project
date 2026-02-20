-- Distinct values of a specific JSON key within TechnicalSpecs_JSON
-- Input: :json_key (e.g. 'size', 'color'), :category, :subcategory
SELECT DISTINCT
    p.Category,
    p.SubCategory,
    :json_key                                               AS Attribute,
    bso.TechnicalSpecs_JSON::json ->> :json_key            AS PossibleValue
FROM BranchSupplyOffer bso
JOIN Product p ON p.ProductID = bso.ProductID
WHERE p.Category    = :category
  AND p.SubCategory = :subcategory
  AND bso.TechnicalSpecs_JSON::json ->> :json_key IS NOT NULL
ORDER BY PossibleValue;