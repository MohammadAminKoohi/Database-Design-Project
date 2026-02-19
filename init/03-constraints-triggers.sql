-- =============================================================================
-- Constraints and Triggers (محدودیت و راهانما)
-- Based on requirements + 2 additional logical constraints
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Discount 0-1, Valid Email Format
-- مقدار تخفیف بین صفر تا یک و فرمت ایمیل صحیح
-- -----------------------------------------------------------------------------

ALTER TABLE BranchSupplyOffer DROP CONSTRAINT IF EXISTS chk_bso_discount;
ALTER TABLE BranchSupplyOffer
  ADD CONSTRAINT chk_bso_discount CHECK (Discount IS NULL OR (Discount >= 0 AND Discount <= 1));

ALTER TABLE Order_Header DROP CONSTRAINT IF EXISTS chk_order_loyalty_discount;
ALTER TABLE Order_Header
  ADD CONSTRAINT chk_order_loyalty_discount CHECK (LoyaltyDiscount IS NULL OR (LoyaltyDiscount >= 0 AND LoyaltyDiscount <= 1));

ALTER TABLE Customer DROP CONSTRAINT IF EXISTS chk_customer_email;
ALTER TABLE Customer
  ADD CONSTRAINT chk_customer_email CHECK (
    Email IS NULL OR
    Email ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  );


-- -----------------------------------------------------------------------------
-- 2. Order Date = Insert Time; Ship Date >= Order Date
-- تاریخ ثبت سفارش با زمان ثبت در پایگاه داده برابر؛ تاریخ ارسال بعد از ثبت یا همان روز
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_order_date_now()
RETURNS TRIGGER AS $$
BEGIN
  NEW.OrderDate := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_date_now ON Order_Header;
CREATE TRIGGER trg_order_date_now
  BEFORE INSERT ON Order_Header
  FOR EACH ROW
  EXECUTE FUNCTION fn_order_date_now();

-- Prevent updating OrderDate to past/future
CREATE OR REPLACE FUNCTION fn_order_date_immutable()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.OrderDate IS DISTINCT FROM NEW.OrderDate THEN
    RAISE EXCEPTION 'OrderDate cannot be modified after insert';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_date_immutable ON Order_Header;
CREATE TRIGGER trg_order_date_immutable
  BEFORE UPDATE ON Order_Header
  FOR EACH ROW
  EXECUTE FUNCTION fn_order_date_immutable();

-- ShipDate >= OrderDate
CREATE OR REPLACE FUNCTION fn_shipment_date_check()
RETURNS TRIGGER AS $$
DECLARE
  ord_date TIMESTAMP;
BEGIN
  SELECT OrderDate INTO ord_date FROM Order_Header WHERE OrderID = NEW.OrderID;
  IF ord_date IS NOT NULL AND NEW.ShipDate IS NOT NULL AND NEW.ShipDate::date < ord_date::date THEN
    RAISE EXCEPTION 'ShipDate must be on or after OrderDate';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_shipment_date_check ON Shipment;
CREATE TRIGGER trg_shipment_date_check
  BEFORE INSERT OR UPDATE ON Shipment
  FOR EACH ROW
  EXECUTE FUNCTION fn_shipment_date_check();


-- -----------------------------------------------------------------------------
-- 3. Item Status Flow: item procurement → awaiting payment → shipped → received
-- وضعیت کالا همیشه مشخص؛ مسیر: پردازش←منتظر پرداخت←ارسال←تحویل
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_order_item_status_flow()
RETURNS TRIGGER AS $$
DECLARE
  allowed_next TEXT[];
  next_ok BOOLEAN := FALSE;
  s TEXT;
BEGIN
  IF OLD.ItemStatus IS NULL OR NEW.ItemStatus IS NULL THEN
    RAISE EXCEPTION 'ItemStatus cannot be NULL';
  END IF;

  -- Allowed transitions (from -> to)
  -- item procurement -> awaiting payment, item procurement
  -- awaiting payment -> shipped, awaiting payment
  -- shipped -> received, shipped, Pending Return Review
  -- received -> received, Pending Return Review
  -- Pending Return Review -> Return Approved, Return Rejected, Pending Return Review
  -- Return Approved/Rejected -> terminal
  allowed_next := CASE OLD.ItemStatus
    WHEN 'item procurement' THEN ARRAY['awaiting payment', 'item procurement']
    WHEN 'awaiting payment' THEN ARRAY['shipped', 'awaiting payment']
    WHEN 'shipped' THEN ARRAY['received', 'shipped', 'Pending Return Review']
    WHEN 'received' THEN ARRAY['received', 'Pending Return Review']
    WHEN 'Pending Return Review' THEN ARRAY['Return Approved', 'Return Rejected', 'Pending Return Review']
    WHEN 'Return Approved' THEN ARRAY['Return Approved']
    WHEN 'Return Rejected' THEN ARRAY['Return Rejected']
    WHEN 'unknown' THEN ARRAY['item procurement', 'awaiting payment', 'shipped', 'received', 'unknown']
    ELSE ARRAY[NEW.ItemStatus]
  END;

  FOREACH s IN ARRAY allowed_next
  LOOP
    IF s = NEW.ItemStatus THEN next_ok := TRUE; EXIT; END IF;
  END LOOP;

  IF NOT next_ok THEN
    RAISE EXCEPTION 'Invalid ItemStatus transition: % -> %', OLD.ItemStatus, NEW.ItemStatus;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_item_status_flow ON OrderItem;
CREATE TRIGGER trg_order_item_status_flow
  BEFORE UPDATE ON OrderItem
  FOR EACH ROW
  WHEN (OLD.ItemStatus IS DISTINCT FROM NEW.ItemStatus)
  EXECUTE FUNCTION fn_order_item_status_flow();

-- On INSERT: ItemStatus not NULL; allow initial + completed statuses (for historical data load)
CREATE OR REPLACE FUNCTION fn_order_item_status_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.ItemStatus IS NULL THEN
    RAISE EXCEPTION 'ItemStatus cannot be NULL';
  END IF;
  IF NEW.ItemStatus NOT IN ('item procurement', 'awaiting payment', 'unknown', 'shipped', 'received',
      'Pending Return Review', 'Return Approved', 'Return Rejected') THEN
    RAISE EXCEPTION 'ItemStatus must be a valid status value';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_item_status_insert ON OrderItem;
CREATE TRIGGER trg_order_item_status_insert
  BEFORE INSERT ON OrderItem
  FOR EACH ROW
  EXECUTE FUNCTION fn_order_item_status_insert();


-- -----------------------------------------------------------------------------
-- 4. Small Business + Low Income: Priority cannot be highest
-- اولویت ارسال برای مشتریان کسبوکار کوچک با درآمد کم نمیتواند حیاتی باشد
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_order_priority_small_business()
RETURNS TRIGGER AS $$
DECLARE
  c_nature VARCHAR(50);
  c_income VARCHAR(50);
  is_low_income BOOLEAN := FALSE;
BEGIN
  IF NEW.Priority <> 'highest' THEN
    RETURN NEW;
  END IF;

  SELECT Nature, IncomeLevel INTO c_nature, c_income
  FROM Customer WHERE CustomerID = NEW.CustomerID;

  IF c_nature <> 'corporate' THEN
    RETURN NEW;
  END IF;

  -- Low income: 'low', 'کم', or numeric < 60000
  is_low_income := (c_income ILIKE '%low%' OR c_income ILIKE '%کم%')
    OR (c_income ~ '^[0-9.]+$' AND (c_income::numeric) < 60000);

  IF is_low_income THEN
    RAISE EXCEPTION 'Priority cannot be highest for small business customers with low income';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_priority_small_business ON Order_Header;
CREATE TRIGGER trg_order_priority_small_business
  BEFORE INSERT OR UPDATE ON Order_Header
  FOR EACH ROW
  EXECUTE FUNCTION fn_order_priority_small_business();


-- -----------------------------------------------------------------------------
-- 5. Large Envelope: no air; Box: no ground
-- پاکت بزرگ هوایی نمیشود؛ جعبه زمینی نمیشود
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_shipment_pack_transport()
RETURNS TRIGGER AS $$
BEGIN
  -- Large envelope: cannot use airmail or air freight
  IF NEW.PackType = 'envelope' AND NEW.PackSize IN ('large-regular', 'large-bubble') THEN
    IF NEW.TransportMethod IN ('airmail', 'air freight') THEN
      RAISE EXCEPTION 'Large envelope cannot be sent by air (airmail or air freight)';
    END IF;
  END IF;

  -- Box: cannot use ground
  IF NEW.PackType = 'box' AND NEW.TransportMethod = 'ground' THEN
    RAISE EXCEPTION 'Box cannot be sent by ground transport';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_shipment_pack_transport ON Shipment;
CREATE TRIGGER trg_shipment_pack_transport
  BEFORE INSERT OR UPDATE ON Shipment
  FOR EACH ROW
  EXECUTE FUNCTION fn_shipment_pack_transport();


-- -----------------------------------------------------------------------------
-- 6. Wallet debt must not exceed customer's debt ceiling (CreditLimit)
-- میزان بدهی کیف پول کاربر نباید از سقف بدهی او بیشتر شود
-- -----------------------------------------------------------------------------

ALTER TABLE Customer DROP CONSTRAINT IF EXISTS chk_customer_debt_limit;
ALTER TABLE Customer
  ADD CONSTRAINT chk_customer_debt_limit CHECK (
    CreditLimit IS NULL OR Debt IS NULL OR Debt <= CreditLimit
  );

-- Wallet balance when negative (debt) must not exceed Customer.CreditLimit
CREATE OR REPLACE FUNCTION fn_wallet_debt_ceiling()
RETURNS TRIGGER AS $$
DECLARE
  cl DECIMAL(15, 2);
BEGIN
  IF NEW.Balance >= 0 THEN
    RETURN NEW;
  END IF;
  SELECT CreditLimit INTO cl FROM Customer WHERE CustomerID = NEW.CustomerID;
  IF cl IS NULL THEN
    RAISE EXCEPTION 'Wallet cannot have negative balance when customer has no credit limit';
  END IF;
  IF (-NEW.Balance) > cl THEN
    RAISE EXCEPTION 'Wallet debt (%) exceeds customer credit limit (%)', (-NEW.Balance), cl;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_wallet_debt_ceiling ON Wallet;
CREATE TRIGGER trg_wallet_debt_ceiling
  BEFORE INSERT OR UPDATE ON Wallet
  FOR EACH ROW
  EXECUTE FUNCTION fn_wallet_debt_ceiling();


-- -----------------------------------------------------------------------------
-- 7. One Manager per Branch; Branch must have Manager
-- یک فرد نمیتواند رئیس بیش از یک شعبه باشد؛ شعبه بدون رئیس نباشد
-- -----------------------------------------------------------------------------

-- Branch.ManagerID is NOT NULL (already in schema)
-- One manager per branch: ManagerID unique per branch - actually one manager can manage one branch.
-- "یک فرد نمیتواند رئیس بیش از یک شعبه باشد" = one person cannot be manager of more than one branch.
-- So ManagerID must be UNIQUE in Branch (one manager -> one branch).
ALTER TABLE Branch DROP CONSTRAINT IF EXISTS uq_branch_manager;
ALTER TABLE Branch ADD CONSTRAINT uq_branch_manager UNIQUE (ManagerID);


-- -----------------------------------------------------------------------------
-- 8. Branch Delete: Keep order data; Anonymize orphaned customer personal info
-- حذف شعبه: حفظ سفارشات؛ حذف اطلاعات شخصی مشتریان بدون سفارش در شعبه دیگر
-- -----------------------------------------------------------------------------

-- Warehouse: CASCADE on branch delete (warehouses are deleted with branch)
ALTER TABLE Warehouse DROP CONSTRAINT IF EXISTS FK_Warehouse_Branch;
ALTER TABLE Warehouse
  ADD CONSTRAINT FK_Warehouse_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID) ON DELETE CASCADE;

-- Make BranchID nullable in Order_Header to allow SET NULL on branch delete
ALTER TABLE Order_Header ALTER COLUMN BranchID DROP NOT NULL;
ALTER TABLE Order_Header DROP CONSTRAINT IF EXISTS FK_Order_Branch;
ALTER TABLE Order_Header
  ADD CONSTRAINT FK_Order_Branch FOREIGN KEY (BranchID) REFERENCES Branch(BranchID) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION fn_branch_delete_anonymize()
RETURNS TRIGGER AS $$
BEGIN
  -- Anonymize customers who had orders ONLY in this branch (after SET NULL, they have BranchID NULL)
  UPDATE Customer
  SET Name = '[deleted]', Email = NULL, Phone = NULL, Age = NULL, Gender = NULL
  WHERE CustomerID IN (
    SELECT CustomerID FROM Order_Header
    WHERE BranchID IS NULL
    EXCEPT
    SELECT CustomerID FROM Order_Header WHERE BranchID IS NOT NULL
  );
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_branch_delete_anonymize ON Branch;
CREATE TRIGGER trg_branch_delete_anonymize
  AFTER DELETE ON Branch
  FOR EACH ROW
  EXECUTE FUNCTION fn_branch_delete_anonymize();


-- -----------------------------------------------------------------------------
-- 9. Return Status Flow: Pending → Approved or Rejected
-- وضعیت مرجوعی: در انتظار بررسی ← تأیید/رد
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_return_request_status_flow()
RETURNS TRIGGER AS $$
BEGIN
  -- NULL = Pending
  IF OLD.ReviewResult IS NULL AND NEW.ReviewResult IS NOT NULL THEN
    IF NEW.ReviewResult NOT IN ('Approved', 'Rejected') THEN
      RAISE EXCEPTION 'ReviewResult must be Approved or Rejected';
    END IF;
    RETURN NEW;
  END IF;

  -- Once Approved/Rejected, cannot change
  IF OLD.ReviewResult IS NOT NULL AND OLD.ReviewResult IS DISTINCT FROM NEW.ReviewResult THEN
    RAISE EXCEPTION 'ReviewResult cannot be changed after decision';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_return_request_status_flow ON ReturnRequest;
CREATE TRIGGER trg_return_request_status_flow
  BEFORE UPDATE ON ReturnRequest
  FOR EACH ROW
  WHEN (OLD.ReviewResult IS DISTINCT FROM NEW.ReviewResult)
  EXECUTE FUNCTION fn_return_request_status_flow();


-- -----------------------------------------------------------------------------
-- 10. Review Score 1-5, Comment < 800 chars
-- امتیاز 1-5؛ متن بازخورد کمتر از 800 حرف
-- -----------------------------------------------------------------------------

ALTER TABLE ProductReview DROP CONSTRAINT IF EXISTS chk_review_score;
ALTER TABLE ProductReview ADD CONSTRAINT chk_review_score CHECK (Score >= 1 AND Score <= 5);

ALTER TABLE ProductReview DROP CONSTRAINT IF EXISTS chk_review_comment_length;
ALTER TABLE ProductReview
  ADD CONSTRAINT chk_review_comment_length CHECK (Comment IS NULL OR LENGTH(Comment) < 800);


-- -----------------------------------------------------------------------------
-- EXTRA 1: TotalAmount >= 0, Quantity > 0, CalculatedItemPrice >= 0
-- -----------------------------------------------------------------------------

ALTER TABLE Order_Header DROP CONSTRAINT IF EXISTS chk_order_total_nonneg;
ALTER TABLE Order_Header ADD CONSTRAINT chk_order_total_nonneg CHECK (TotalAmount IS NULL OR TotalAmount >= 0);

ALTER TABLE OrderItem DROP CONSTRAINT IF EXISTS chk_order_item_qty;
ALTER TABLE OrderItem ADD CONSTRAINT chk_order_item_qty CHECK (Quantity > 0);

ALTER TABLE OrderItem DROP CONSTRAINT IF EXISTS chk_order_item_price;
ALTER TABLE OrderItem ADD CONSTRAINT chk_order_item_price CHECK (CalculatedItemPrice IS NULL OR CalculatedItemPrice >= 0);


-- -----------------------------------------------------------------------------
-- EXTRA 2: WalletTransaction Amount non-zero (Deposit > 0, Payment < 0)
-- -----------------------------------------------------------------------------

ALTER TABLE WalletTransaction DROP CONSTRAINT IF EXISTS chk_wallet_trans_amount;
ALTER TABLE WalletTransaction
  ADD CONSTRAINT chk_wallet_trans_amount CHECK (Amount IS NOT NULL AND Amount <> 0);
