deallocate wallet_turnover;

PREPARE wallet_turnover AS

SELECT
    c.Gender,
    c.IncomeLevel,
    EXTRACT(YEAR FROM wt.date) AS transaction_year,
    COUNT(DISTINCT c.CustomerID) AS customer_count,
    AVG(abs_turnover.total_turnover) AS avg_wallet_turnover
FROM Customer c
JOIN Wallet w ON c.CustomerID = w.CustomerID
JOIN (
    SELECT
        wt.customerid,
        EXTRACT(YEAR FROM wt.date) AS yr,
        SUM(ABS(wt.Amount)) AS total_turnover
    FROM WalletTransaction wt
    GROUP BY wt.customerid, EXTRACT(YEAR FROM wt.date)
) abs_turnover ON w.customerid = abs_turnover.customerid
JOIN WalletTransaction wt ON w.customerid = wt.customerid
GROUP BY c.Gender, c.IncomeLevel, EXTRACT(YEAR FROM wt.date)
ORDER BY transaction_year, c.Gender, c.IncomeLevel;

execute wallet_turnover;