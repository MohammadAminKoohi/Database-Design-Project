SELECT
    turnover.Year,
    c.Gender,
    c.IncomeLevel,
    COUNT(DISTINCT c.CustomerID)       AS CustomerCount,
    ROUND(AVG(turnover.TotalTurnover), 2) AS AvgWalletTurnover
FROM (
    SELECT
        CustomerID,
        EXTRACT(YEAR FROM Date) AS Year,
        SUM(Amount)             AS TotalTurnover
    FROM WalletTransaction
    GROUP BY CustomerID, EXTRACT(YEAR FROM Date)
) turnover
JOIN Customer c ON c.CustomerID = turnover.CustomerID
JOIN Wallet w   ON w.CustomerID = c.CustomerID
GROUP BY
    turnover.Year,
    c.Gender,
    c.IncomeLevel
ORDER BY
    turnover.Year,
    c.Gender,
    c.IncomeLevel;