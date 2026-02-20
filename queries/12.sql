deallocate customer_value;

prepare customer_value as

WITH direct_payments AS (
    SELECT
        oh.CustomerID,
        SUM(oh.TotalAmount) AS TotalOrderPayments
    FROM Order_Header oh
    WHERE oh.PaymentMethod IN ('credit card', 'debit card', 'cash', 'wallet')
    GROUP BY oh.CustomerID
),
bnpl_repayments AS (
    SELECT
        oh.CustomerID,
        SUM(rh.Amount) AS TotalBNPLRepaid
    FROM RepaymentHistory rh
    JOIN Order_Header oh ON oh.OrderID = rh.OrderID
    GROUP BY oh.CustomerID
),
approved_returns AS (
    SELECT
        oh.CustomerID,
        SUM(oi.CalculatedItemPrice) AS TotalRefunded
    FROM ReturnRequest rr
    JOIN OrderItem oi
        ON oi.OrderID = rr.OrderID
        AND oi.ProductID = rr.ProductID
    JOIN Order_Header oh ON oh.OrderID = rr.OrderID
    WHERE rr.ReviewResult = 'Approved'
    GROUP BY oh.CustomerID
),
tax_paid AS (
    SELECT
        oh.CustomerID,
        SUM(oi.CalculatedItemPrice * p.TaxAmount) AS TotalTaxPaid
    FROM OrderItem oi
    JOIN Order_Header oh ON oh.OrderID = oi.OrderID
    JOIN Product p ON p.ProductID = oi.ProductID
    WHERE NOT EXISTS (
        SELECT 1
        FROM ReturnRequest rr
        WHERE rr.OrderID = oi.OrderID
          AND rr.ProductID = oi.ProductID
          AND rr.ReviewResult = 'Approved'
    )
    GROUP BY oh.CustomerID
)
SELECT
    c.CustomerID,
    c.Name                                                      AS CustomerName,
    COALESCE(dp.TotalOrderPayments, 0)                          AS DirectPayments,
    COALESCE(bp.TotalBNPLRepaid, 0)                             AS BNPLRepayments,
    COALESCE(ar.TotalRefunded, 0)                               AS ApprovedReturnRefunds,
    COALESCE(tp.TotalTaxPaid, 0)                                AS TotalTaxPaid,
    ROUND(
        COALESCE(dp.TotalOrderPayments, 0)
        + COALESCE(bp.TotalBNPLRepaid, 0)
        - COALESCE(ar.TotalRefunded, 0)
        + COALESCE(tp.TotalTaxPaid, 0),
    2)                                                          AS TrueCustomerValue
FROM Customer c
LEFT JOIN direct_payments dp   ON dp.CustomerID = c.CustomerID
LEFT JOIN bnpl_repayments bp   ON bp.CustomerID = c.CustomerID
LEFT JOIN approved_returns ar  ON ar.CustomerID = c.CustomerID
LEFT JOIN tax_paid tp          ON tp.CustomerID = c.CustomerID
ORDER BY TrueCustomerValue DESC;

execute customer_value;