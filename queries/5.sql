deallocate delayed_products;

PREPARE delayed_products AS

SELECT
    oh.OrderID,
    oh.OrderDate,
    s.ShipDate,
    s.type
FROM Order_Header oh
JOIN Shipment s ON oh.OrderID = s.OrderID
WHERE
    (s.type = 'same-day' AND s.ShipDate::date != oh.OrderDate::date)
    OR
    (s.type = 'standard' AND s.ShipDate > oh.OrderDate + INTERVAL '2 days')
ORDER BY oh.OrderDate DESC;

execute delayed_products;
