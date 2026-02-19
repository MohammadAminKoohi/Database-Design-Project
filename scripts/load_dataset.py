#!/usr/bin/env python3
"""
Database Population Script for BiDibiKala
Imports provided data from dataset/ folder into PostgreSQL.
Run after: docker-compose up -d postgres
"""
import os
import csv
import random
from pathlib import Path
from datetime import datetime
from decimal import Decimal

import psycopg2
from dotenv import load_dotenv

load_dotenv()

# Paths
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATASET_DIR = PROJECT_ROOT / "dataset"

# Payment method mapping (BDBKala -> schema)
PAYMENT_MAP = {
    "In-App Wallet": "wallet",
    "Debit Card": "debit card",
    "Credit Card": "credit card",
    "Cash": "cash",
    "BNPL": "BNPL",
}

# Priority mapping
PRIORITY_MAP = {
    "Urgent": "high",
    "Critical": "highest",
    "Medium": "medium",
    "Low": "low",
    "Not Specified": "lowest",
}

# Transport method mapping
TRANSPORT_MAP = {
    "Air (Freight)": "air freight",
    "Air (Post)": "airmail",
    "Ground": "ground",
}

# Pack type/size mapping
def parse_packaging(pack_str):
    if not pack_str:
        return None, None
    s = str(pack_str).lower()
    if "box" in s:
        if "large" in s:
            return "box", "large"
        if "medium" in s:
            return "box", "medium"
        if "small" in s:
            return "box", "small"
        return "box", "medium"
    if "envelope" in s:
        return "envelope", "small-regular"
    return None, None


def get_conn():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "bdbkala"),
        user=os.getenv("PGUSER", "admin"),
        password=os.getenv("PGPASSWORD", "admin"),
    )


def load_branch_product_suppliers(conn):
    """Load Managers, Branches, Products, Suppliers, BranchSupplyOffer from branch_product_suppliers.csv"""
    print("Loading branch_product_suppliers.csv...")
    path = DATASET_DIR / "branch_product_suppliers.csv"
    if not path.exists():
        raise FileNotFoundError(f"Missing {path}")

    branches = {}  # (branch_name, address) -> (BranchID, manager_name, phone)
    products = {}  # (name, cat, subcat) -> ProductID
    suppliers = {}  # name -> (SupplierID, phone, address)
    offers = []  # (BranchID, ProductID, SupplierID, supply_price, lead_time)

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            mname = row["manager_name"].strip()
            bname = row["branch_name"].strip()
            baddr = row["address"].strip()
            bkey = (bname, baddr)
            if bkey not in branches:
                branches[bkey] = (len(branches) + 1, mname, row["phone"].strip())

            pkey = (row["product_name"].strip(), row["category"].strip(), row["sub_category"].strip())
            if pkey not in products:
                products[pkey] = len(products) + 1

            sname = row["supplier_name"].strip()
            if sname not in suppliers:
                suppliers[sname] = (len(suppliers) + 1, row.get("supplier_phone", ""), row.get("supplier_address", ""))

            bid = branches[bkey][0]
            pid = products[pkey]
            sid = suppliers[sname][0]
            supply_price = Decimal(str(row["supply_price"]))
            lead_time = int(row["lead_time_days"])
            offers.append((bid, pid, sid, supply_price, lead_time))

    cur = conn.cursor()

    for (bname, baddr), (bid, mname, phone) in branches.items():
        cur.execute("INSERT INTO Manager (ManagerID, Name) VALUES (%s, %s) ON CONFLICT (ManagerID) DO NOTHING", (bid, mname))
        cur.execute(
            "INSERT INTO Branch (BranchID, Name, Address, Phone, ManagerID) VALUES (%s, %s, %s, %s, %s) ON CONFLICT (BranchID) DO NOTHING",
            (bid, bname, baddr, phone or None, bid),
        )

    for (pname, cat, subcat), pid in products.items():
        cur.execute(
            "INSERT INTO Product (ProductID, Name, Category, SubCategory, TaxAmount) VALUES (%s, %s, %s, %s, 0.10) ON CONFLICT (ProductID) DO NOTHING",
            (pid, pname, cat or None, subcat or None),
        )

    for sname, (sid, phone, addr) in suppliers.items():
        cur.execute(
            "INSERT INTO Supplier (SupplierID, Name, Phone, Address) VALUES (%s, %s, %s, %s) ON CONFLICT (SupplierID) DO NOTHING",
            (sid, sname, phone or None, addr or None),
        )

    for bid, pid, sid, supply_price, lead_time in offers:
        selling_price = round(supply_price * Decimal("1.3"), 2)
        cur.execute(
            """INSERT INTO BranchSupplyOffer (BranchID, ProductID, SupplierID, SellingPrice, SupplyPrice, LeadTime, Discount, IsAvailable)
               VALUES (%s, %s, %s, %s, %s, %s, 0, TRUE) ON CONFLICT (BranchID, ProductID, SupplierID) DO NOTHING""",
            (bid, pid, sid, selling_price, supply_price, lead_time),
        )

    conn.commit()
    cur.close()
    print(f"  Managers: {len(branches)}, Branches: {len(branches)}, Products: {len(products)}, Suppliers: {len(suppliers)}, Offers: {len(offers)}")
    return {"branches": branches, "products": products, "suppliers": suppliers, "branch_ids": [b[0] for b in branches.values()]}


def load_products_properties(conn, products_by_name):
    """Update Product.BaseInfo from products_properties.csv"""
    print("Loading products_properties.csv...")
    path = DATASET_DIR / "products_properties.csv"
    if not path.exists():
        return

    cur = conn.cursor()
    count = 0
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            pname = row["product_name"].strip()
            attrs = row.get("attributes", "")
            # Find product ID by name (products dict has (name, cat, subcat) -> id)
            for (name, cat, subcat), pid in products_by_name.items():
                if name == pname:
                    cur.execute("UPDATE Product SET BaseInfo = %s WHERE ProductID = %s", (attrs or None, pid))
                    count += 1
                    break
    conn.commit()
    cur.close()
    print(f"  Updated {count} products with BaseInfo")


def load_bdbkala_full(conn, branch_ids, product_map):
    """Load Customers, Orders, OrderItems, Shipments from BDBKala_full.csv"""
    print("Loading BDBKala_full.csv...")
    path = DATASET_DIR / "BDBKala_full.csv"
    if not path.exists():
        raise FileNotFoundError(f"Missing {path}")

    initial_max_pid = max(product_map.values()) if product_map else 0
    next_pid = initial_max_pid + 1

    def get_product_id(row):
        nonlocal next_pid
        pkey = (row["Product Name"].strip(), row["Product Category"].strip(), row["Product Sub-Category"].strip())
        if pkey not in product_map:
            product_map[pkey] = next_pid
            next_pid += 1
        return product_map[pkey]

    customers = {}  # email -> (CustomerID, name, phone, age, gender, income, nature)
    orders = {}  # OrderID -> (OrderDate, Priority, PaymentMethod, CustomerID, BranchID, items, shipment_info)
    order_items = []

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                order_id = int(row["Order ID"])
            except (ValueError, KeyError):
                continue

            email_raw = (row.get("Email") or "").strip()
            if not email_raw:
                continue
            email = email_raw.replace("@@", "@")  # Fix common typo for constraint

            # Customer
            cname = (row.get("Customer Name") or "").strip()
            phone = (row.get("Phone") or "").strip()
            age_val = row.get("Customer Age")
            age = int(age_val) if age_val and str(age_val).isdigit() else None
            gender_raw = (row.get("Gender") or "").strip().lower()
            gender = "M" if "male" in gender_raw and "female" not in gender_raw else "F" if "female" in gender_raw else None
            income_val = row.get("Income")
            income = Decimal(str(income_val)) if income_val else None
            seg = (row.get("Customer Segment") or "Consumer").strip()
            nature = "corporate" if seg in ("Corporate", "Small Business") else "consumer"

            if email not in customers:
                customers[email] = (len(customers) + 1, cname, phone, age, gender, income, nature)

            cid = customers[email][0]
            pid = get_product_id(row)
            if not pid:
                continue

            try:
                qty = max(1, int(float(row.get("Order Quantity", 1) or 1)))
            except (ValueError, TypeError):
                qty = 1
            unit_price = Decimal(str(row.get("Unit Price", 0) or 0))
            discount = Decimal(str(row.get("Discount", 0) or 0))
            item_price = max(Decimal("0"), round(unit_price * (1 - discount) * qty, 2))

            priority_raw = (row.get("Order Priority") or "Low").strip()
            priority = PRIORITY_MAP.get(priority_raw, "low")
            payment_raw = (row.get("Payment Method") or "").strip()
            payment = PAYMENT_MAP.get(payment_raw, "credit card")
            order_date_str = row.get("Order Date", "2020-01-01")
            try:
                order_date = datetime.strptime(order_date_str[:10], "%Y-%m-%d")
            except ValueError:
                order_date = datetime(2020, 1, 1)

            ship_addr = (row.get("Shipping Address") or "").strip()
            ship_date_str = row.get("Ship Date", "")
            ship_date = None
            if ship_date_str:
                try:
                    ship_date = datetime.strptime(ship_date_str[:10], "%Y-%m-%d")
                except ValueError:
                    pass
            city = (row.get("City") or "").strip()
            zip_code = (row.get("Zip Code") or "").strip()
            ship_cost = Decimal(str(row.get("Shipping Cost", 0) or 0))
            transport_raw = (row.get("Ship Mode") or "").strip()
            transport = TRANSPORT_MAP.get(transport_raw, "ground")
            pack_type, pack_size = parse_packaging(row.get("Packaging", ""))
            if pack_type == "box" and transport == "ground":
                transport = "airmail"  # Box cannot use ground (constraint)
            ship_type = "same-day" if "Express" in (row.get("Shipping Method") or "") else "standard"

            if order_id not in orders:
                branch_id = random.choice(branch_ids) if branch_ids else 1
                orders[order_id] = {
                    "date": order_date,
                    "priority": priority,
                    "payment": payment,
                    "customer_id": cid,
                    "branch_id": branch_id,
                    "items": [],
                    "ship_addr": ship_addr,
                    "ship_date": ship_date,
                    "city": city,
                    "zip_code": zip_code,
                    "ship_cost": ship_cost,
                    "transport": transport,
                    "pack_type": pack_type,
                    "pack_size": pack_size,
                    "ship_type": ship_type,
                }

            orders[order_id]["items"].append((pid, qty, item_price))

    # Deduplicate order items by (OrderID, ProductID) - sum quantities
    order_item_agg = {}
    for oid, data in orders.items():
        for pid, qty, price in data["items"]:
            key = (oid, pid)
            if key not in order_item_agg:
                order_item_agg[key] = [0, Decimal("0")]
            order_item_agg[key][0] += qty
            order_item_agg[key][1] += price

    cur = conn.cursor()

    # Insert any new products discovered from BDBKala (not in branch_product_suppliers)
    for (pname, cat, subcat), pid in product_map.items():
        if pid > initial_max_pid:
            cur.execute(
                "INSERT INTO Product (ProductID, Name, Category, SubCategory, TaxAmount) VALUES (%s, %s, %s, %s, 0.10) ON CONFLICT (ProductID) DO NOTHING",
                (pid, pname, cat or None, subcat or None),
            )

    for email, (cid, cname, phone, age, gender, income, nature) in customers.items():
        tier = random.choice(["new", "regular", "special"])
        cur.execute(
            """INSERT INTO Customer (CustomerID, Name, Phone, Email, Age, Gender, IncomeLevel, Nature, Tier, TaxAmount, LoyaltyPoints)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 0.10, 0) ON CONFLICT (CustomerID) DO NOTHING""",
            (cid, cname, phone or None, email, age, gender, str(income) if income else None, nature, tier),
        )

    cid_to_nature_income = {cid: (nat, inc) for _, (cid, _, _, _, _, inc, nat) in customers.items()}

    for oid, data in orders.items():
        total = sum(order_item_agg[(oid, pid)][1] for pid in set(p for p, _, _ in data["items"]) if (oid, pid) in order_item_agg)
        total = round(total + data["ship_cost"], 2)
        total = max(Decimal("0"), total)  # Ensure non-negative for constraint
        priority = data["priority"]
        cid = data["customer_id"]
        nat, inc = cid_to_nature_income.get(cid, (None, None))
        if priority == "highest" and nat == "corporate" and inc is not None:
            try:
                inc_val = float(inc) if not isinstance(inc, (int, float)) else inc
                if inc_val < 60000:
                    priority = "high"
            except (ValueError, TypeError):
                pass
        cur.execute(
            """INSERT INTO Order_Header (OrderID, OrderDate, Priority, TotalAmount, PaymentMethod, LoyaltyDiscount, CustomerID, BranchID)
               VALUES (%s, %s, %s, %s, %s, 0, %s, %s) ON CONFLICT (OrderID) DO NOTHING""",
            (oid, data["date"], priority, total, data["payment"], cid, data["branch_id"]),
        )

    for (oid, pid), (qty, price) in order_item_agg.items():
        price = max(Decimal("0"), price)  # Ensure non-negative for constraint
        cur.execute(
            """INSERT INTO OrderItem (OrderID, ProductID, Quantity, CalculatedItemPrice, ItemStatus)
               VALUES (%s, %s, %s, %s, 'received') ON CONFLICT (OrderID, ProductID) DO NOTHING""",
            (oid, pid, qty, price),
        )

    for oid, data in orders.items():
        cur.execute("SELECT OrderDate FROM Order_Header WHERE OrderID = %s", (oid,))
        row = cur.fetchone()
        order_date = row[0] if row else None
        ship_date = data["ship_date"]
        if order_date and ship_date and ship_date < order_date:
            ship_date = order_date  # ShipDate must be >= OrderDate (constraint)
        tracking = f"TRK{oid:08d}"
        cur.execute(
            """INSERT INTO Shipment (ShipmentID, TrackingCode, ShipDate, RecipientAddress, City, ZipCode, Type, TransportMethod, Cost, PackType, PackSize, OrderID)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING""",
            (oid, tracking, ship_date, data["ship_addr"] or None, data["city"] or None, data["zip_code"] or None,
             data["ship_type"], data["transport"], data["ship_cost"], data["pack_type"], data["pack_size"], oid),
        )

    conn.commit()
    cur.close()
    print(f"  Customers: {len(customers)}, Orders: {len(orders)}, OrderItems: {len(order_item_agg)}")
    return {"customers": customers, "orders": orders, "order_to_customer": {oid: d["customer_id"] for oid, d in orders.items()}}


def load_wallet_balances(conn, _unused=None):
    """Load Wallet table from wallet_balances.csv. Create Customer records for new customers.
    Ensures all customers have a Wallet (balance 0 if not in file)."""
    print("Loading wallet_balances.csv...")
    path = DATASET_DIR / "wallet_balances.csv"

    cur = conn.cursor()
    cur.execute("SELECT COALESCE(MAX(CustomerID), 0) FROM Customer")
    next_cid = cur.fetchone()[0] + 1
    cur.execute("SELECT CustomerID, Email FROM Customer")
    email_to_cid = {r[1]: r[0] for r in cur.fetchall() if r[1]}
    all_cids = set(email_to_cid.values())
    wallets = {}

    if path.exists():
        with open(path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                email = (row.get("customer_email") or "").strip()
                if not email:
                    continue
                balance = Decimal(str(row.get("wallet_balance", 0) or 0))
                name = (row.get("customer_name") or email.split("@")[0]).strip()
                phone = (row.get("customer_phone") or "").strip()
                if email not in email_to_cid:
                    cid = next_cid
                    next_cid += 1
                    email_to_cid[email] = cid
                    cur.execute(
                        """INSERT INTO Customer (CustomerID, Name, Phone, Email, Nature, Tier, TaxAmount, LoyaltyPoints)
                           VALUES (%s, %s, %s, %s, 'consumer', 'regular', 0.10, 0) ON CONFLICT (CustomerID) DO NOTHING""",
                        (cid, name, phone or None, email),
                    )
                cid = email_to_cid[email]
                wallets[cid] = balance
                all_cids.add(cid)

    for cid in all_cids:
        balance = wallets.get(cid, Decimal("0"))
        cur.execute(
            "INSERT INTO Wallet (CustomerID, Balance) VALUES (%s, %s) ON CONFLICT (CustomerID) DO UPDATE SET Balance = EXCLUDED.Balance",
            (cid, balance),
        )

    conn.commit()
    cur.close()
    print(f"  Wallets: {len(all_cids)} (from file: {len(wallets)})")
    return wallets


def load_reviews(conn, order_to_customer, product_map):
    """Load ProductReview from reviews.csv. Match by Order ID and Product name."""
    print("Loading reviews.csv...")
    path = DATASET_DIR / "reviews.csv"
    if not path.exists():
        return

    cur = conn.cursor()
    count = 0
    seen = set()
    name_to_pid = {pname: pid for (pname, _pc, _ps), pid in product_map.items()}

    # Increase field size limit for CSV (reviews have large Image column with binary data)
    import sys
    max_int = sys.maxsize
    while True:
        try:
            csv.field_size_limit(max_int)
            break
        except OverflowError:
            max_int //= 2

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                order_id = int(row.get("Order ID", 0))
            except (ValueError, TypeError):
                continue
            if order_id not in order_to_customer:
                continue
            cid = order_to_customer[order_id]
            pname = (row.get("Product Name") or "").strip()
            pcat = (row.get("Product Category") or "").strip()
            psub = (row.get("Product Sub-Category") or "").strip()
            pkey = (pname, pcat, psub)
            pid = product_map.get(pkey) or name_to_pid.get(pname)
            if not pid:
                continue
            key = (cid, pid)
            if key in seen:
                continue
            seen.add(key)
            comment = (row.get("Comment") or "").strip()[:2000]
            score = random.randint(1, 5)
            cur.execute(
                """INSERT INTO ProductReview (CustomerID, ProductID, Score, Comment, IsPublic)
                   VALUES (%s, %s, %s, %s, TRUE) ON CONFLICT (CustomerID, ProductID) DO NOTHING""",
                (cid, pid, score, comment or None),
            )
            count += 1

    conn.commit()
    cur.close()
    print(f"  Reviews: {count}")


def main():
    conn = get_conn()
    try:
        data = load_branch_product_suppliers(conn)
        product_map = data["products"]
        branch_ids = data["branch_ids"]

        load_products_properties(conn, product_map)

        bdb_data = load_bdbkala_full(conn, branch_ids, product_map)
        order_to_customer = bdb_data["order_to_customer"]

        load_wallet_balances(conn, bdb_data.get("order_to_customer", {}))
        load_reviews(conn, order_to_customer, product_map)

        print("\nData load complete. Run generate_extra_data.py and reconstruct_wallet.py next.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
