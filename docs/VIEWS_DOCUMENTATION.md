# Views Documentation (بخش چهارم: کاربرد با دید)

This document describes the five views designed for specific unit access requirements.

---

## 1. Warehouse Unit — Unsent Product Orders

**View:** `v_warehouse_unsent_product_orders`

**Requirement:** واحد انبار نیاز به دسترسی به تعداد سفارش از هر کالای ارسال نشده (در وضعیت پردازش و منتظر پرداخت) بدون دانستن مشخصات سفارش‌دهنده دارد.

**Purpose:** Count of orders per product for items not yet shipped (processing or awaiting payment), without customer details.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| ProductID | INT | Product identifier |
| ProductName | VARCHAR | Product name |
| Category | VARCHAR | Product category |
| SubCategory | VARCHAR | Product sub-category |
| TotalQuantity | BIGINT | Sum of quantities across orders |
| OrderCount | BIGINT | Number of distinct orders |

**Filter:** `ItemStatus IN ('awaiting payment', 'item procurement')`

**Usage:**
```sql
SELECT * FROM v_warehouse_unsent_product_orders;
```

---

## 2. Accounting Unit — Daily Sales and Profit (Materialized View)

**View:** `mv_daily_sales_profit`

**Requirement:** واحد حسابداری نیاز به دسترسی به مجموع فروش و سود هر روز دارد. نیازی به داده‌های لحظه‌ای روز جاری وجود ندارد و کافی است مجموع در انتهای هر روز حساب شود. از دید تجسم‌یافته (Materialized View) استفاده کنید.

**Purpose:** Daily totals for sales and profit. Refreshed at end of day (no real-time requirement).

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| sale_date | DATE | Order date |
| total_sales | DECIMAL | Sum of Order_Header.TotalAmount |
| total_profit | DECIMAL | total_sales − sum(Quantity × SupplyPrice) |

**Profit calculation:** Revenue from `Order_Header.TotalAmount` minus cost from `BranchSupplyOffer.SupplyPrice × OrderItem.Quantity`.

**Refresh (run at end of day):**
```sql
REFRESH MATERIALIZED VIEW mv_daily_sales_profit;
```

**Usage:**
```sql
SELECT * FROM mv_daily_sales_profit ORDER BY sale_date DESC;
```

---

## 3. Branch Manager — Branch Customers

**View:** `v_branch_manager_customers`

**Requirement:** رئیس هر شعبه نیاز به دسترسی به اطلاعات مشتریان خود دارد. این اطلاعات شامل مشخصات شخصی مشتریانی است که در آن شعبه حداقل یک سفارش داشتند.

**Purpose:** Personal details of customers who have at least one order in the branch.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| BranchID | INT | Branch identifier |
| BranchName | VARCHAR | Branch name |
| ManagerID | INT | Manager identifier |
| ManagerName | VARCHAR | Manager name |
| CustomerID | INT | Customer identifier |
| CustomerName | VARCHAR | Customer name |
| Phone | VARCHAR | Customer phone |
| Email | VARCHAR | Customer email |
| Age | INT | Customer age |
| Gender | CHAR | Customer gender |
| IncomeLevel | VARCHAR | Income level |
| Nature | VARCHAR | consumer / corporate |
| Tier | VARCHAR | new / regular / special |

**Usage (for a specific branch manager):**
```sql
SELECT * FROM v_branch_manager_customers WHERE BranchID = 1;
-- or
SELECT * FROM v_branch_manager_customers WHERE ManagerID = 1;
```

---

## 4. Marketing Unit — Customer Loyalty

**View:** `v_marketing_customer_loyalty`

**Requirement:** واحد بازاریابی نیاز به دسترسی به اطلاعات وفاداری مشتریان دارد. این اطلاعات شامل مجموع مبلغ خریدهای انجام‌شده توسط هر مشتری، امتیاز وفاداری محاسبه‌شده، و سطح عضویت او در برنامه وفاداری است.

**Purpose:** Loyalty metrics: total purchase amount, loyalty points, and membership tier per customer.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| CustomerID | INT | Customer identifier |
| CustomerName | VARCHAR | Customer name |
| Email | VARCHAR | Customer email |
| total_purchase_amount | DECIMAL | Sum of all order totals |
| loyalty_points | INT | From Customer.LoyaltyPoints |
| membership_tier | VARCHAR | new / regular / special |

**Usage:**
```sql
SELECT * FROM v_marketing_customer_loyalty ORDER BY total_purchase_amount DESC;
```

---

## 5. Support Unit — Pending Return Orders

**View:** `v_support_pending_returns`

**Requirement:** واحد پشتیبانی نیاز به دسترسی به سفارش‌های دارای درخواست مرجوعی که در انتظار بررسی هستند، دارد. این دسترسی شامل کلیه اقلامی است که وضعیت مرجوعی آنها هنوز تعیین تکلیف نشده است.

**Purpose:** Orders with return requests pending review, including all items whose return status is not yet determined.

**Columns:**
| Column | Type | Description |
|--------|------|-------------|
| ReturnID | INT | Return request identifier |
| OrderID | INT | Order identifier |
| ProductID | INT | Product identifier |
| ProductName | VARCHAR | Product name |
| RequestDate | TIMESTAMP | When return was requested |
| Reason | TEXT | Return reason |
| Quantity | INT | Item quantity |
| CalculatedItemPrice | DECIMAL | Item price |
| ItemStatus | VARCHAR | Order item status |
| OrderDate | TIMESTAMP | Order date |
| CustomerID | INT | Customer identifier |

**Filter:** `ReturnRequest.ReviewResult IS NULL` (pending review)

**Usage:**
```sql
SELECT * FROM v_support_pending_returns;
```

---

## Applying the Views

If the database was created before `02-views.sql` was added:

```bash
psql -h localhost -U admin -d bdbkala -f init/02-views.sql
```

Or from `psql`:
```sql
\i init/02-views.sql
```

---

## Summary

| # | Unit | View Name | Type |
|---|------|-----------|------|
| 1 | Warehouse | v_warehouse_unsent_product_orders | VIEW |
| 2 | Accounting | mv_daily_sales_profit | MATERIALIZED VIEW |
| 3 | Branch Manager | v_branch_manager_customers | VIEW |
| 4 | Marketing | v_marketing_customer_loyalty | VIEW |
| 5 | Support | v_support_pending_returns | VIEW |
