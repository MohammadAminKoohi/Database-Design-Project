#!/usr/bin/env python3
"""
Generate missing data for BiDibiKala using Faker.
Creates: Warehouses, WarehouseInventory, additional orders (reusing customers/products),
ReturnRequest, RepaymentHistory for BNPL orders.
"""
import os
import random
from datetime import datetime, timedelta
from decimal import Decimal

import psycopg2
from faker import Faker
from dotenv import load_dotenv

load_dotenv()
fake = Faker()

def get_conn():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "bdbkala"),
        user=os.getenv("PGUSER", "admin"),
        password=os.getenv("PGPASSWORD", "admin"),
    )


def create_warehouses(conn):
    """Create one warehouse per branch."""
    cur = conn.cursor()
    cur.execute("SELECT BranchID, Name, Address FROM Branch")
    branches = cur.fetchall()
    cur.execute("SELECT COALESCE(MAX(WarehouseID), 0) FROM Warehouse")
    next_id = cur.fetchone()[0] + 1

    for bid, bname, baddr in branches:
        cur.execute(
            "INSERT INTO Warehouse (WarehouseID, Name, Address, BranchID) VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
            (next_id, f"Warehouse {bname}", (baddr or "") + " - Warehouse", bid),
        )
        next_id += 1
    conn.commit()
    cur.close()
    print(f"Created {len(branches)} warehouses")


def create_warehouse_inventory(conn):
    """Populate WarehouseInventory from BranchSupplyOffer - each branch's warehouse gets products it supplies."""
    cur = conn.cursor()
    cur.execute("SELECT w.BranchID, w.WarehouseID FROM Warehouse w JOIN Branch b ON w.BranchID = b.BranchID")
    branch_warehouse = {r[0]: r[1] for r in cur.fetchall()}
    cur.execute("SELECT BranchID, ProductID FROM BranchSupplyOffer")
    for bid, pid in cur.fetchall():
        wid = branch_warehouse.get(bid)
        if wid:
            qty = random.randint(10, 500)
            cur.execute(
                """INSERT INTO WarehouseInventory (WarehouseID, ProductID, Quantity)
                   VALUES (%s, %s, %s) ON CONFLICT (WarehouseID, ProductID) DO UPDATE SET Quantity = WarehouseInventory.Quantity + EXCLUDED.Quantity""",
                (wid, pid, qty),
            )
    conn.commit()
    cur.close()
    print("Populated WarehouseInventory")


def _cannot_have_highest_priority(nature, income_level):
    """Match DB trigger: corporate + low income cannot have highest priority."""
    if nature != "corporate" or not income_level:
        return False
    income = str(income_level).strip()
    if "low" in income.lower() or "کم" in income:
        return True
    try:
        return float(income) < 60000
    except (ValueError, TypeError):
        return False


def create_additional_orders(conn, count=500):
    """Create additional orders reusing existing customers, products, branches. Vary payment method and status."""
    cur = conn.cursor()
    cur.execute("SELECT CustomerID, Nature, IncomeLevel FROM Customer")
    customers = list(cur.fetchall())  # (cid, nature, income_level)
    cur.execute("SELECT BranchID FROM Branch")
    branches = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT ProductID, Name FROM Product")
    products = list(cur.fetchall())
    cur.execute("SELECT COALESCE(MAX(OrderID), 0) FROM Order_Header")
    next_oid = cur.fetchone()[0] + 1
    cur.execute("SELECT COALESCE(MAX(ShipmentID), 0) FROM Shipment")
    next_sid = cur.fetchone()[0] + 1

    payments = ["credit card", "debit card", "cash", "wallet", "BNPL"]
    priorities = ["lowest", "low", "medium", "high", "highest"]
    priorities_no_highest = ["lowest", "low", "medium", "high"]
    # DB trigger allows only initial statuses on INSERT: item procurement, awaiting payment, unknown
    item_statuses = ["item procurement", "awaiting payment"]

    for _ in range(min(count, len(customers) * 2)):
        oid = next_oid
        next_oid += 1
        cid, nature, income_level = random.choice(customers)
        bid = random.choice(branches)
        payment = random.choice(payments)
        priority = random.choice(priorities)
        if priority == "highest" and _cannot_have_highest_priority(nature, income_level):
            priority = random.choice(priorities_no_highest)
        num_items = random.randint(1, 5)
        chosen = random.sample(products, min(num_items, len(products)))
        total = Decimal("0")
        items_to_insert = []
        for pid, pname in chosen:
            qty = random.randint(1, 3)
            price = Decimal(str(round(random.uniform(10, 200), 2)))
            item_total = price * qty
            total += item_total
            status = random.choice(item_statuses)
            items_to_insert.append((oid, pid, qty, item_total, status))
        ship_cost = Decimal(str(round(random.uniform(5, 30), 2)))
        total += ship_cost
        cur.execute(
            """INSERT INTO Order_Header (OrderID, OrderDate, Priority, TotalAmount, PaymentMethod, LoyaltyDiscount, CustomerID, BranchID)
               VALUES (%s, CURRENT_TIMESTAMP, %s, %s, %s, 0, %s, %s) ON CONFLICT (OrderID) DO NOTHING""",
            (oid, priority, total, payment, cid, bid),
        )
        cur.execute("SELECT OrderDate FROM Order_Header WHERE OrderID = %s", (oid,))
        order_date = cur.fetchone()[0]
        for oid_i, pid, qty, item_total, status in items_to_insert:
            cur.execute(
                "INSERT INTO OrderItem (OrderID, ProductID, Quantity, CalculatedItemPrice, ItemStatus) VALUES (%s, %s, %s, %s, %s) ON CONFLICT (OrderID, ProductID) DO NOTHING",
                (oid_i, pid, qty, item_total, status),
            )
        ship_date = order_date + timedelta(days=random.randint(1, 7))
        # Box cannot use ground (constraint); use airmail or air freight
        transport = random.choice(["airmail", "air freight"])
        cur.execute(
            """INSERT INTO Shipment (ShipmentID, TrackingCode, ShipDate, RecipientAddress, City, ZipCode, Type, TransportMethod, Cost, PackType, PackSize, OrderID)
               VALUES (%s, %s, %s, %s, %s, %s, 'standard', %s, %s, 'box', 'medium', %s) ON CONFLICT (OrderID) DO NOTHING""",
            (oid, f"TRK{oid:08d}", ship_date, fake.address(), fake.city(), fake.zipcode(), transport, ship_cost, oid),
        )
        next_sid = max(next_sid, oid + 1)

    conn.commit()
    cur.close()
    print(f"Created {count} additional orders")


def create_repayment_history(conn):
    """Create RepaymentHistory for BNPL orders (installment payments)."""
    cur = conn.cursor()
    cur.execute("SELECT OrderID, TotalAmount, OrderDate FROM Order_Header WHERE PaymentMethod = 'BNPL'")
    bnpl_orders = cur.fetchall()
    for oid, total, order_date in bnpl_orders:
        if total <= 0:
            continue
        num_payments = random.randint(2, 4)
        amt_per = round(total / num_payments, 2)
        methods = ["credit card", "debit card", "wallet"]
        base = order_date if isinstance(order_date, datetime) else datetime.combine(order_date, datetime.min.time())
        for i in range(num_payments):
            pay_date = base + timedelta(days=30 * (i + 1))
            cur.execute(
                "INSERT INTO RepaymentHistory (OrderID, PaymentDate, Amount, PaymentMethod) VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                (oid, pay_date, amt_per, random.choice(methods)),
            )
    conn.commit()
    cur.close()
    print(f"Created RepaymentHistory for {len(bnpl_orders)} BNPL orders")


def create_return_requests(conn, count=50):
    """Create ReturnRequest for some received order items."""
    cur = conn.cursor()
    cur.execute("SELECT OrderID, ProductID FROM OrderItem WHERE ItemStatus = 'received' LIMIT 5000")
    items = cur.fetchall()
    if not items:
        cur.close()
        return
    chosen = random.sample(items, min(count, len(items)))
    cur.execute("SELECT COALESCE(MAX(ReturnID), 0) FROM ReturnRequest")
    next_rid = cur.fetchone()[0] + 1
    reasons = ["Defective product", "Wrong size", "Changed mind", "Received damaged"]
    for oid, pid in chosen:
        cur.execute(
            """INSERT INTO ReturnRequest (ReturnID, RequestDate, Reason, ReviewResult, DecisionDate, OrderID, ProductID)
               VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING""",
            (next_rid, fake.date_time_between(start_date="-1y"), random.choice(reasons), random.choice(["Approved", "Rejected"]), fake.date_time_between(start_date="-6m"), oid, pid),
        )
        next_rid += 1
    conn.commit()
    cur.close()
    print(f"Created {len(chosen)} return requests")


def main():
    conn = get_conn()
    try:
        create_warehouses(conn)
        create_warehouse_inventory(conn)
        create_additional_orders(conn, count=300)
        create_repayment_history(conn)
        create_return_requests(conn, count=50)
        print("\nExtra data generation complete.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
