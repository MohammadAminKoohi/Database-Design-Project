-- Input: :customer_id, :purchase_amount
SELECT
    c.CustomerID,
    c.Name                                          AS CustomerName,
    c.Debt                                          AS CurrentDebt,
    c.CreditLimit,
    c.CreditLimit - c.Debt                          AS RemainingCredit,
    :purchase_amount::DECIMAL                       AS RequestedAmount,
    CASE
        WHEN (c.CreditLimit - c.Debt) >= :purchase_amount
        THEN 'BNPL payment is allowed'
        ELSE 'Insufficient BNPL credit'
    END                                             AS BNPLEligibility
FROM Customer c
WHERE c.CustomerID = :customer_id;