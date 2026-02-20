deallocate BNPL_credit;

PREPARE BNPL_credit AS

SELECT
    c.CustomerID,
    c.Name AS customer_name,
    c.CreditLimit AS bnpl_limit,
    c.Debt AS current_debt,
    $1::numeric AS requested_purchase,
    (c.CreditLimit - c.Debt) AS available_credit,
    CASE
        WHEN (c.Debt + $1::numeric) <= c.CreditLimit
        THEN 'YES'
        ELSE 'NO'
    END AS bnpl_eligible
FROM Customer c
WHERE c.CustomerID = $2;

execute BNPL_credit(10000, 10);