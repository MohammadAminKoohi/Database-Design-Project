DEALLOCATE check_bnpl_eligibility;

PREPARE check_bnpl_eligibility(int, decimal) AS
SELECT
    Debt AS Current_Debt,
    CreditLimit AS Credit_Limit,
    $2 AS Purchase_Amount,
    CASE
        WHEN (Debt + $2) <= CreditLimit THEN TRUE
        ELSE FALSE
    END AS Can_Pay_With_BNPL,
    (CreditLimit - Debt) AS Remaining_Credit
FROM
    Customer
WHERE
    CustomerID = $1;

-- give small debt money to get true
EXECUTE check_bnpl_eligibility(1, 50000000);