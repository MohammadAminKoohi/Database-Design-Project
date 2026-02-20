CREATE INDEX idx_oi_order_product ON OrderItem (OrderID, ProductID);
CREATE INDEX idx_oi_product_order ON OrderItem (ProductID, OrderID);


drop index if exists idx_oi_order_product;
drop index if exists idx_oi_product_order;