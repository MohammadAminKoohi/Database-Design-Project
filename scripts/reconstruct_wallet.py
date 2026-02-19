#!/usr/bin/env python3
"""
Wallet Transaction History Reconstruction for BiDibiKala.

The third-party wallet provider only gave final balances. We reconstruct
WalletTransaction history to be strictly consistent with:
1) Completed purchases paid via wallet (Payment transactions)
2) Final wallet balances

Methodology:
- For each customer: final_balance = sum(Deposits) - sum(Payments)
- Payments = amounts from orders where PaymentMethod='wallet'
- Therefore: sum(Deposits) = final_balance + sum(Payments)
- We create Payment transactions for each wallet order, then Deposit
  transactions (one or more) that sum to the required total.
"""
import os
from datetime import datetime, timedelta
from decimal import Decimal

import psycopg2
from dotenv import load_dotenv

load_dotenv()


def get_conn():
    return psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "bdbkala"),
        user=os.getenv("PGUSER", "admin"),
        password=os.getenv("PGPASSWORD", "admin"),
    )


def reconstruct(conn):
    cur = conn.cursor()

    # Get all wallets with final balance
    cur.execute("SELECT CustomerID, Balance FROM Wallet")
    wallets = {r[0]: Decimal(str(r[1])) for r in cur.fetchall()}

    # Get wallet payments from completed orders (PaymentMethod = 'wallet')
    cur.execute(
        """SELECT CustomerID, OrderID, TotalAmount, OrderDate
           FROM Order_Header
           WHERE PaymentMethod = 'wallet' AND TotalAmount > 0"""
    )
    wallet_orders = cur.fetchall()

    # Per-customer: total paid via wallet
    customer_payments = {}  # cid -> [(order_id, amount, date), ...]
    for cid, oid, amount, odate in wallet_orders:
        if cid not in customer_payments:
            customer_payments[cid] = []
        customer_payments[cid].append((oid, Decimal(str(amount)), odate))

    # Clear existing wallet transactions (we are reconstructing)
    cur.execute("DELETE FROM WalletTransaction")
    conn.commit()

    cur.execute("SELECT COALESCE(MAX(TransactionID), 0) FROM WalletTransaction")
    next_tid = 1

    transactions = []

    for cid, final_balance in wallets.items():
        payments_list = customer_payments.get(cid, [])
        total_payments = sum(p[1] for p in payments_list)

        # Create Payment transactions for each wallet order
        for oid, amount, odate in payments_list:
            transactions.append((next_tid, cid, "Payment", -amount, odate))
            next_tid += 1

        # Required deposits: final_balance + total_payments (since balance = deposits - payments)
        required_deposits = final_balance + total_payments

        if required_deposits > 0:
            # Create Deposit transactions (must occur BEFORE payments chronologically)
            earliest_pay = _earliest_date(payments_list)
            if required_deposits <= 10000:
                dep_date = earliest_pay - timedelta(days=7)  # Deposit before first payment
                transactions.append((next_tid, cid, "Deposit", required_deposits, dep_date))
                next_tid += 1
            else:
                num_deposits = min(5, int(required_deposits / 1000) + 1)
                amt_each = round(required_deposits / num_deposits, 2)
                remainder = required_deposits - amt_each * (num_deposits - 1)
                for i in range(num_deposits):
                    amt = remainder if i == num_deposits - 1 else amt_each
                    dep_date = earliest_pay - timedelta(days=30 * (num_deposits - i))
                    transactions.append((next_tid, cid, "Deposit", amt, dep_date))
                    next_tid += 1

        elif required_deposits < 0:
            # Final balance is negative relative to payments - customer overspent?
            # In a real system this might mean debt. For consistency we need
            # sum(Deposits) - sum(Payments) = final_balance
            # So sum(Deposits) = final_balance + sum(Payments) which is < total_payments
            # This means we have more payments than deposits - add a "negative deposit" or
            # reduce payments. Schema only has Deposit and Payment.
            # Payment decreases balance. Deposit increases.
            # final_balance = deposits - payments. If final_balance < 0 and we have payments,
            # we need deposits < payments. So required_deposits = final_balance + total_payments.
            # If that's negative, we can't have negative deposits. So we need to add extra
            # Payment transactions? No - that would make it worse.
            # Actually: the formula is correct. required_deposits can be negative if
            # final_balance is very negative (e.g. -1000) and total_payments is small (e.g. 100).
            # Then we need deposits = -1000 + 100 = -900. We can't create negative deposits.
            # Solution: If required_deposits < 0, the data is inconsistent. We could:
            # 1) Set final_balance to 0 and not create deposits
            # 2) Create a "correction" - treat it as the customer had prior debt
            # For strict consistency: we must have sum(Deposits) - sum(Payments) = final_balance.
            # If final_balance is negative, we need sum(Deposits) < sum(Payments). The only way
            # is to have fewer Payment records or smaller amounts. But we're deriving Payments
            # from actual orders - we can't change those.
            # So we must have sum(Deposits) = final_balance + sum(Payments). If this is negative,
            # we cannot achieve it with Deposit transactions. We'll skip deposits for this customer
            # (leave balance as-is from payments only) and log a warning.
            # Actually the Wallet.Balance is the final balance. So we're reconstructing history
            # to be consistent. If final_balance + total_payments < 0, it means the customer
            # paid more via wallet than they have. That could mean they had a negative balance
            # (overdraft) or the data is wrong. We'll add a small deposit to make it work
            # or set deposits to 0 and accept the inconsistency.
            pass  # Skip - no deposits when required_deposits < 0

    # Sort by (CustomerID, Date) so deposits come before payments chronologically per customer
    transactions.sort(key=lambda t: (t[1], t[4]))
    for i, (_, cid, ttype, amount, tdate) in enumerate(transactions):
        tid = i + 1
        cur.execute(
            "INSERT INTO WalletTransaction (TransactionID, CustomerID, Type, Amount, Date) VALUES (%s, %s, %s, %s, %s)",
            (tid, cid, ttype, amount, tdate),
        )

    conn.commit()
    cur.close()
    return len(transactions)


def _earliest_date(payments_list):
    if not payments_list:
        return datetime(2020, 1, 1)
    dates = [p[2] for p in payments_list]
    d = min(dates)
    if hasattr(d, "date"):
        return datetime.combine(d.date() if hasattr(d, "date") else d, datetime.min.time())
    return datetime(2020, 1, 1)


def verify(conn):
    """Verify reconstruction: for each customer, sum(Deposits)-sum(Payments) should equal Wallet.Balance"""
    cur = conn.cursor()
    cur.execute("SELECT CustomerID, Balance FROM Wallet")
    errors = []
    for cid, expected in cur.fetchall():
        cur.execute(
            """SELECT Type, Amount FROM WalletTransaction WHERE CustomerID = %s""",
            (cid,),
        )
        balance = Decimal("0")
        for ttype, amount in cur.fetchall():
            amt = Decimal(str(amount))
            if ttype == "Deposit":
                balance += amt
            else:
                balance -= abs(amt)
        expected = Decimal(str(expected))
        if abs(balance - expected) > Decimal("0.01"):
            errors.append((cid, float(balance), float(expected)))
    cur.close()
    return errors


def main():
    conn = get_conn()
    try:
        n = reconstruct(conn)
        print(f"Created {n} wallet transactions.")
        errs = verify(conn)
        if errs:
            print(f"WARNING: {len(errs)} customers have balance mismatch: {errs[:5]}...")
        else:
            print("Verification passed: all wallet balances consistent.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
