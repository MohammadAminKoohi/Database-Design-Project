CREATE INDEX idx_order_header_branch_order ON Order_Header (OrderID, BranchID);
CREATE INDEX idx_orderitem_product_order ON OrderItem (ProductID, OrderID, Quantity);

drop index idx_order_header_branch_order;
drop index idx_orderitem_product_order;