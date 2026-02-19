# Phase Report: Database Population & Data Generation

**Project:** BiDibiKala Database Design  
**Phase:** Database Population, Data Generation, and Wallet Reconstruction  
**Date:** February 2025

---

## 1. Executive Summary

This phase focused on populating the BiDibiKala PostgreSQL database with provided datasets, generating missing data using Faker, and reconstructing wallet transaction history from final balances and completed purchases. All tasks were completed successfully with verification.

---

## 2. Initial Understanding

### 2.1 Database Schema (16 Tables)

The schema (`init/01-schema.sql`) defines the following structure:

| # | Table | Purpose |
|---|-------|---------|
| 1 | Manager | Branch managers |
| 2 | Branch | Store branches (linked to Manager) |
| 3 | Customer | Customer profiles (demographics, tier, nature) |
| 4 | Wallet | 1:1 with Customer, stores balance |
| 5 | WalletTransaction | Deposit/Payment history per customer |
| 6 | Product | Product catalog |
| 7 | Supplier | Product suppliers |
| 8 | Warehouse | Warehouses per branch |
| 9 | Order_Header | Order metadata (customer, branch, payment, total) |
| 10 | Shipment | Shipping details per order |
| 11 | RepaymentHistory | BNPL installment payments |
| 12 | OrderItem | Line items (order, product, qty, price, status) |
| 13 | ReturnRequest | Product return requests |
| 14 | ProductReview | Customer reviews (score, comment) |
| 15 | WarehouseInventory | Stock levels per warehouse/product |
| 16 | BranchSupplyOffer | Branch–Product–Supplier offers (prices, lead time) |

### 2.2 Provided Datasets (5 Files)

| File | Rows (approx) | Fields | Purpose |
|------|---------------|--------|---------|
| **BDBKala_full.csv** | ~27,800 | Order ID, Date, Priority, Quantity, Status, Payment Method, Product Name, Category, Sub-Category, Unit Price, Cost, Discount, Shipping Address, Method, Ship Date, Ship Mode, Packaging, Shipping Cost, Region, City, Zip, Ratings, Customer Segment, Customer Name, Age, Email, Phone, Gender, Income | Main order/customer/shipment data |
| **branch_product_suppliers.csv** | ~5,245 | branch_name, address, phone, manager_name, product_name, category, sub_category, supplier_name, supplier_phone, supplier_address, supply_price, lead_time_days | Branch, product, supplier, and supply offers |
| **wallet_balances.csv** | ~25,260 | customer_name, customer_email, customer_phone, wallet_balance | Final wallet balances only (no transaction history) |
| **reviews.csv** | ~136 | Order ID, Product Name, Category, Sub-Category, Comment, Image | Product reviews |
| **products_properties.csv** | ~625 | product_name, category, sub_category, attributes (JSON) | Product attributes/BaseInfo |

### 2.3 Environment

- **Database:** PostgreSQL 16 (Docker)
- **Connection:** `localhost:5432`, database `bdbkala`, user `admin`
- **Init:** Schema auto-loaded from `init/01-schema.sql` on first container start

---

## 3. Task Requirements

### 3.1 Importing Provided Data

Import all provided datasets into the database, mapping CSV columns to schema tables and handling type conversions.

### 3.2 Generating Missing Data

For tables/entities not covered by the datasets, generate data using tools such as Faker, following the database design.

### 3.3 Reusing Existing Data

Reuse existing customers, products, and branches where possible instead of generating new ones (e.g., vary branch, status, payment type on existing orders).

### 3.4 Wallet Data Reconstruction

**Problem:** The wallet provider only supplied final balances, not transaction history.

**Requirement:** Reconstruct `WalletTransaction` history so that it is consistent with:
- Completed purchases (wallet payments)
- Final wallet balances

---

## 4. Implementation

### 4.1 Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/load_dataset.py` | Import all 5 provided datasets |
| `scripts/generate_extra_data.py` | Generate missing data with Faker |
| `scripts/reconstruct_wallet.py` | Reconstruct wallet transaction history |
| `scripts/run_all.py` | Run all scripts in order |

### 4.2 Data Mapping & Transformations

#### Payment Method Mapping (BDBKala → Schema)

| Source | Target |
|--------|--------|
| In-App Wallet | wallet |
| Debit Card | debit card |
| Credit Card | credit card |
| Cash | cash |
| BNPL | BNPL |

#### Priority Mapping

| Source | Target |
|--------|--------|
| Urgent | high |
| Critical | highest |
| Medium | medium |
| Low | low |
| Not Specified | lowest |

#### Transport Method Mapping

| Source | Target |
|--------|--------|
| Air (Freight) | air freight |
| Air (Post) | airmail |
| Ground | ground |

#### Packaging Mapping

- `Box Large` → PackType=box, PackSize=large  
- `Box Medium` → PackType=box, PackSize=medium  
- `Box Small` → PackType=box, PackSize=small  

#### Customer Segment → Nature

- Consumer → consumer  
- Corporate, Small Business → corporate  

---

## 5. Gaps Handled in Load Script

| Gap | Handling |
|-----|----------|
| **BDBKala has no Branch** | Orders randomly assigned to branches from `branch_product_suppliers` |
| **Products in BDBKala not in branch_product_suppliers** | New products created on-the-fly and inserted into `Product` |
| **Wallet customers not in BDBKala** | New `Customer` records created from `wallet_balances.csv` (name, email, phone) |
| **Reviews missing Score** | Random score 1–5 generated |
| **Reviews Image column** | Binary image data not stored; `ImageData` left NULL |
| **Invalid Order Quantity** | Negative/invalid values coerced to 1 |
| **Large CSV fields (reviews)** | `csv.field_size_limit` increased for binary Image column |

---

## 6. Generated Data (Faker)

### 6.1 Warehouse

- One warehouse per branch
- Name: `"Warehouse {BranchName}"`
- Address: branch address + `" - Warehouse"`

### 6.2 WarehouseInventory

- For each (Branch, Product) in `BranchSupplyOffer`, the branch’s warehouse gets that product
- Quantity: random 10–500 per product

### 6.3 Additional Orders (300)

- Reuse existing customers, products, branches
- Random: payment method, priority, item status
- Faker: order date, shipping address, city, zip
- 1–5 items per order, quantity 1–3, price 10–200

### 6.4 RepaymentHistory

- For each BNPL order: 2–4 installment payments
- Amount per payment: total / number of payments
- Payment dates: 30 days apart after order date
- Payment methods: credit card, debit card, wallet

### 6.5 ReturnRequest (50)

- Random received `OrderItem`s
- Reasons: "Defective product", "Wrong size", "Changed mind", "Received damaged"
- ReviewResult: "Approved" or "Rejected"
- Faker: RequestDate, DecisionDate

---

## 7. Wallet Reconstruction

### 7.1 Methodology

For each customer:

```
final_balance = sum(Deposits) - sum(Payments)
```

- **Payments:** From orders with `PaymentMethod = 'wallet'` (one Payment per order)
- **Required deposits:** `required_deposits = final_balance + sum(Payments)`

### 7.2 Deposit Creation

- If `required_deposits > 0`:
  - ≤ 10,000: single deposit 7 days before first payment
  - > 10,000: split into up to 5 deposits, dated before first payment
- If `required_deposits ≤ 0`: no deposits (overspent / inconsistent case)

### 7.3 Verification

After reconstruction, the script checks that for each customer:

```
sum(Deposits) - sum(Payments) = Wallet.Balance
```

All customers passed verification.

---

## 8. Results

### 8.1 Load Summary (from run)

| Entity | Count |
|--------|-------|
| Managers | 9 |
| Branches | 10 |
| Products | 616+ |
| Suppliers | 20 |
| BranchSupplyOffer | 5,244 |
| Customers | 1,999 |
| Orders | 25,560 (25,260 + 300) |
| OrderItems | 126,726+ |
| Shipments | 25,560 |
| Wallets | 1,999 |
| WalletTransactions | 15,254 |
| Warehouses | 10 |
| WarehouseInventory | Populated |
| RepaymentHistory | 64 BNPL orders |
| ReturnRequests | 50 |

### 8.2 File Structure

```
Database-Design-Project/
├── init/
│   └── 01-schema.sql          # Schema definition
├── dataset/
│   ├── BDBKala_full.csv
│   ├── branch_product_suppliers.csv
│   ├── wallet_balances.csv
│   ├── reviews.csv
│   └── products_properties.csv
├── scripts/
│   ├── load_dataset.py
│   ├── generate_extra_data.py
│   ├── reconstruct_wallet.py
│   └── run_all.py
├── docs/
│   └── PHASE_REPORT_DATABASE_POPULATION.md
├── requirements.txt
├── docker-compose.yml
└── .env
```

### 8.3 Dependencies

```
psycopg2-binary>=2.9.9
pandas>=2.0.0
Faker>=22.0.0
python-dotenv>=1.0.0
```

---

## 9. How to Run

```bash
# 1. Start PostgreSQL
docker compose up -d postgres

# 2. Create virtual environment
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3. Run all scripts
python scripts/run_all.py
```

Or run individually:

```bash
python scripts/load_dataset.py
python scripts/generate_extra_data.py
python scripts/reconstruct_wallet.py
```

---

## 10. Conclusion

This phase completed:

1. **Import** of all 5 provided datasets into the schema  
2. **Generation** of missing data (warehouses, inventory, extra orders, returns, repayments)  
3. **Reuse** of existing customers, products, and branches  
4. **Wallet reconstruction** consistent with purchases and final balances  

The database is populated and ready for querying and analysis.
