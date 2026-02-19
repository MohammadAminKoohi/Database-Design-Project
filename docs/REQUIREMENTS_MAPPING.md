# Requirements Mapping: Database Population & Wallet Reconstruction

This document maps the project's Python scripts to the stated requirements.

---

## 1. Importing Provided Data

**Requirement:** *"The complete data for BiDibiKala, along with a portion of the data for the new requirements, has been provided to you. Import this into the databases. For this task, you can use online tools such as tableconvert, konbert, convertcsv, or any other method you prefer."*

**Implementation:** `scripts/load_dataset.py`

- **Method used:** Python + `psycopg2` (programmatic import; equivalent in outcome to using convertcsv/tableconvert/konbert to produce SQL or CSV for bulk load).
- **What is imported:** The provided `BDBKala_full.csv` is read and mapped into the database schema:
  - **Complete BiDibiKala data:** Manager, Branch, Customer, Wallet, Product, Supplier, Warehouse, Order_Header, OrderItem, Shipment. Rows are derived from the CSV (regions, customers, products, orders, line items, shipping).
  - **Portion of new-requirements data:** The CSV already carries fields that support new requirements (e.g. order status, payment method, shipping method, packaging). These are imported as-is into the corresponding columns (e.g. `Order_Header.PaymentMethod`, `OrderItem.ItemStatus`, `Shipment.Type` / `TransportMethod` / `PackType` / `PackSize`).
- **TotalAmount:** For each order, `Order_Header.TotalAmount` is set to the sum of (item price × quantity) plus shipment cost, so it can be used later for wallet reconstruction.

**Run:** `python scripts/load_dataset.py` (optionally with a path to another CSV).

---

## 2. Generating Missing Data

**Requirement:** *"For the remaining data that has not been provided, generate it based on your own database design. Use available tools such as programming libraries (like Faker) or AI language model-based online tools (like Fabricate), and insert this generated data into the database."*

**Implementation:** `scripts/generate_extra_data.py`

- **Tool used:** Faker (programming library) for realistic text and dates.
- **Generated (missing) data:**
  - **Wallet.Balance** — Simulated “final wallet balance” per customer (third party only provided this; actual reconstruction of history is in the next step).
  - **ReturnRequest** — For some order items that have return-related statuses: request date, reason, review result, decision date.
  - **ProductReview** — For a subset of (Customer, Product) pairs that have orders: score, comment, IsPublic.
  - **RepaymentHistory** — For orders with PaymentMethod = BNPL: installment payments (date, amount, payment method).
  - **BranchSupplyOffer** — For (Branch, Product) pairs that appear in orders: selling/supply price, lead time, discount.
  - **WarehouseInventory** — Quantities for a subset of (Warehouse, Product) pairs.

All of this is inserted into the database and is consistent with the existing schema and FKs.

---

## 3. Reusing Existing Data

**Requirement:** *"In general, try to repurpose the provided data for the new requirements as much as possible to avoid the need to generate data with repetitive structures. For example, you can modify the branch, status, and payment type of existing orders. You can also use existing users and products to register new orders."*

**Implementation:** `scripts/generate_extra_data.py`

- **Modifying existing orders (repurposing):**
  - **Branch:** A subset of existing orders has `Order_Header.BranchID` changed to another valid branch.
  - **Status:** A subset of existing `OrderItem` rows has `ItemStatus` set to return-related values: `Pending Return Review`, `Return Approved`, `Return Rejected`.
  - **Payment type:** A subset of existing orders has `PaymentMethod` set to `BNPL` (so they can have RepaymentHistory).
- **Using existing users and products for new orders:**
  - New orders are created with new `OrderID`s, but using only existing `CustomerID` and `ProductID` (and `BranchID`). For each new order: one or more order lines (existing products, generated quantity and unit price), one shipment row, and `TotalAmount` set to the sum of line totals plus shipping cost. No new customers or products are invented; only new order/shipment/line records.

---

## 4. Wallet Data Reconstruction

**Requirement:** *"The third-party wallet service provider has not been cooperative and has only provided DibiKala with the users' final wallet balances. DibiKala must reconstruct the wallet history using the information from the completed purchases. The wallet transaction history must be strictly consistent with both the completed purchases and the final balances. Methodology: You may accomplish this using any method of your choice."*

**Implementation:** `scripts/reconstruct_wallet.py`

- **Inputs:**
  1. **Final balances:** `Wallet.Balance` for each customer (as provided by the third party; in our pipeline these are set in `generate_extra_data.py` for simulation).
  2. **Completed purchases paid with wallet:** `Order_Header` rows where `PaymentMethod = 'wallet'` and `TotalAmount` is not null.
- **What the script does:**
  - Deletes existing `WalletTransaction` rows (so the table can be rebuilt from scratch).
  - For each customer, computes total wallet payments = sum of `TotalAmount` of that customer’s orders with `PaymentMethod = 'wallet'`.
  - For each customer, inserts:
    - One or more **Deposit** transactions so that total deposits minus total payments equals that customer’s **Wallet.Balance**.
    - One **Payment** per wallet-paid order, with amount = that order’s `TotalAmount` and date = order date.
- **Consistency:**
  - **With completed purchases:** Every wallet-paid order has exactly one Payment with the same amount and a consistent date.
  - **With final balances:** For every customer, `sum(Deposits) - sum(Payments) = Wallet.Balance` (within a small numeric tolerance in validation).

**Run:** After `load_dataset.py` and after `Wallet.Balance` is set (e.g. by `generate_extra_data.py`):  
`python scripts/reconstruct_wallet.py`

---

## Execution Order

1. `python scripts/load_dataset.py` — Import provided data.
2. `python scripts/generate_extra_data.py` — Generate missing data, reuse existing data (modify orders + new orders).
3. `python scripts/reconstruct_wallet.py` — Reconstruct wallet history from final balances and wallet-paid orders.
4. `python scripts/validate_data.py` — Optionally validate table counts and wallet consistency.
