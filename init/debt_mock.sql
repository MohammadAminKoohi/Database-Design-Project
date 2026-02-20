UPDATE Customer
SET
    -- Assign CreditLimit based on Tier
    CreditLimit = CASE
        WHEN Tier = 'special' THEN (5000 + (RANDOM() * 5000))::DECIMAL(15,2) -- 5,000 to 10,000
        WHEN Tier = 'regular' THEN (1500 + (RANDOM() * 2500))::DECIMAL(15,2) -- 1,500 to 4,000
        WHEN Tier = 'new'     THEN (500 + (RANDOM() * 500))::DECIMAL(15,2)    -- 500 to 1,000
        ELSE 1000.00 -- Default for any null tiers
    END,

    -- Assign Debt as a random percentage (0% to 70%) of their NEW CreditLimit
    -- We use a subquery or a calculation to ensure Debt <= CreditLimit
    Debt = CASE
        WHEN Tier = 'special' THEN (RANDOM() * 3000)::DECIMAL(15,2)
        WHEN Tier = 'regular' THEN (RANDOM() * 1000)::DECIMAL(15,2)
        ELSE (RANDOM() * 200)::DECIMAL(15,2)
    END
where customerid > 0;