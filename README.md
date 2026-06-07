# Superstore Sales Analytics Platform 

An advanced relational schema migration and end-to-end business intelligence engine designed for **Microsoft SQL Server (T-SQL)**. This project handles database normalization, data deduplication windows, complex subqueries, multi-layer Common Table Expressions (CTEs), and intricate window functions over partitions to extract revenue metrics from the Sample Superstore dataset.

---

## 📂 Project Architecture & Table Topology

The system breaks down a flat, denormalized ledger dataset (`superstore_raw`) into an optimized relational model consisting of **two dimension tables** and **one central fact table** to improve storage footprint, indexing capability, and transactional integrity.


```

```
   [ superstore_raw ] (Flat Staging Ledger)
           │
           ├───► [ customers ] (Dimension Table)
           ├───► [ products ]  (Dimension Table)
           └───► [ orders ]    (Central Fact Table)

```

```

---

## 🛠️ Step 1: Database DDL Setup & Normalization Schema

This phase builds the relational structural layout using strong column constraints, primary keys, and foreign keys.

```sql
-- Safely drop existing tables in reverse dependency order to avoid foreign key blocks
IF OBJECT_ID('dbo.orders', 'U') IS NOT NULL DROP TABLE dbo.orders;
IF OBJECT_ID('dbo.customers', 'U') IS NOT NULL DROP TABLE dbo.customers;
IF OBJECT_ID('dbo.products', 'U') IS NOT NULL DROP TABLE dbo.products;

-- Create Normalized Customers Dimension Table
CREATE TABLE customers (
    Customer_ID VARCHAR(50) PRIMARY KEY,
    Customer_Name VARCHAR(100) NOT NULL,
    Segment VARCHAR(50) NOT NULL
);

-- Create Normalized Products Dimension Table
CREATE TABLE products (
    Product_ID VARCHAR(50) PRIMARY KEY,
    Category VARCHAR(50) NOT NULL,
    Sub_Category VARCHAR(50) NOT NULL,
    Product_Name VARCHAR(255) NOT NULL
);

-- Create Centralized Orders Fact Table
CREATE TABLE orders (
    Row_ID INT PRIMARY KEY,
    Order_ID VARCHAR(50) NOT NULL,
    Order_Date VARCHAR(50) NOT NULL,  
    Ship_Date VARCHAR(50) NOT NULL,   
    Ship_Mode VARCHAR(50) NOT NULL,
    Customer_ID VARCHAR(50) NOT NULL,
    Product_ID VARCHAR(50) NOT NULL,
    Sales FLOAT NOT NULL,
    Quantity INT NOT NULL,
    Discount FLOAT NOT NULL,
    Profit FLOAT NOT NULL,
    City VARCHAR(100) NOT NULL,
    State VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    Postal_Code VARCHAR(50) NULL,
    Region VARCHAR(50) NOT NULL,
    FOREIGN KEY (Customer_ID) REFERENCES customers(Customer_ID),
    FOREIGN KEY (Product_ID) REFERENCES products(Product_ID)
);

```

### Data Loading & Window Deduplication

When parsing raw flat logs, product names often vary slightly across transaction rows, which can trigger primary key violations. We deploy `SELECT DISTINCT` alongside a `ROW_NUMBER()` partitioning subquery window to cleanly populate our dimensions:

```sql
-- Populate Customers Dimension using SELECT DISTINCT
INSERT INTO customers (Customer_ID, Customer_Name, Segment)
SELECT DISTINCT Customer_ID, Customer_Name, Segment 
FROM superstore_raw;

-- Populate Products Dimension using ROW_NUMBER to isolate unique Product_IDs
INSERT INTO products (Product_ID, Category, Sub_Category, Product_Name)
SELECT Product_ID, Category, Sub_Category, Product_Name 
FROM (
    SELECT Product_ID, Category, Sub_Category, Product_Name, 
           ROW_NUMBER() OVER (PARTITION BY Product_ID ORDER BY Row_ID DESC) as rn
    FROM superstore_raw
) AS prod_src 
WHERE rn = 1;

-- Ingest transaction records into the central fact table
INSERT INTO orders 
SELECT Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode, Customer_ID, Product_ID, Sales, Quantity, Discount, Profit, City, State, Country, Postal_Code, Region
FROM superstore_raw;

```

* **Ingestion Metrics:** `customers` loaded **793** records; `products` loaded **1,862** records; `orders` loaded **9,994** records.

---

## 🔍 Step 2: Core Analytical Queries

### Query 1: Find all orders where sales are greater than the average sales (Subquery)

*Calculates the shop's global line-item sales mean ($\approx \$229.86$) using a scalar subquery to find high-performing transactions.*

```sql
SELECT Row_ID, Order_ID, Customer_ID, Sales
FROM orders
WHERE Sales > (SELECT AVG(Sales) FROM orders)
ORDER BY Sales DESC;

```

### Query 2: Find the highest sales order for each customer (Subquery)

*Uses a correlated subquery within a `HAVING` clause to isolate the single largest combined order total for every customer profile.*

```sql
SELECT o1.Customer_ID, o1.Order_ID, SUM(o1.Sales) AS Highest_Order_Sales
FROM orders o1
GROUP BY o1.Customer_ID, o1.Order_ID
HAVING SUM(o1.Sales) = (
    SELECT MAX(Order_Total)
    FROM (
        SELECT Order_ID, SUM(Sales) AS Order_Total
        FROM orders o2
        WHERE o2.Customer_ID = o1.Customer_ID
        GROUP BY Order_ID
    ) AS inner_customer_orders
)
ORDER BY Highest_Order_Sales DESC;

```

### Query 3: Calculate total sales for each customer (CTE)

*Isolates and aggregates gross customer spending inside an independent temporary Common Table Expression.*

```sql
WITH CustomerSales AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT Customer_ID, ROUND(Total_Sales, 2) AS Total_Sales
FROM CustomerSales
ORDER BY Total_Sales DESC;

```

### Query 4: Find customers whose total sales are above average (CTE + Subquery)

*Computes customer spending trends inside a CTE, then dynamically aggregates the customer-level baseline mean ($\approx \$2,896.85$) via a subquery.*

```sql
WITH CustomerSales AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT Customer_ID, ROUND(Total_Sales, 2) AS Above_Avg_Customer_Sales
FROM CustomerSales
WHERE Total_Sales > (SELECT AVG(Total_Sales) FROM CustomerSales)
ORDER BY Above_Avg_Customer_Sales DESC;

```

### Query 5: Rank all customers based on total sales (Window Function)

*Applies a `RANK()` window function over customer sales aggregates to assign competitive positioning.*

```sql
WITH CustomerSalesTotals AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT 
    Customer_ID,
    ROUND(Total_Sales, 2) AS Cumulative_Sales,
    RANK() OVER (ORDER BY Total_Sales DESC) AS Sales_Rank
FROM CustomerSalesTotals;

```

### Query 6: Assign row numbers to each order within a customer (Window Function + PARTITION BY)

*Partitions transaction histories by client account, running an incremental line counter that resets for every distinct customer.*

```sql
SELECT 
    Customer_ID, Order_ID, Order_Date, Sales,
    ROW_NUMBER() OVER (
        PARTITION BY Customer_ID 
        ORDER BY Order_Date DESC, Order_ID ASC
    ) AS Order_Row_Num
FROM orders;

```

### Query 7: Display top 3 customers based on total sales (Window Function)

*Filters down a ranked window set to extract only the top 3 spots on the leaderboard.*

```sql
WITH CustomerSales AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
),
RankedCustomerSet AS (
    SELECT Customer_ID, Total_Sales,
           RANK() OVER (ORDER BY Total_Sales DESC) AS Customer_Rank
    FROM CustomerSales
)
SELECT r.Customer_ID, ROUND(r.Total_Sales, 2) AS Total_Sales, r.Customer_Rank
FROM RankedCustomerSet r
WHERE r.Customer_Rank <= 3;

```

---

## 🔀 Step 3: Final Combined Query

Ties the dimensional attributes (`Customer_Name`) to aggregated metrics via a **JOIN**, **CTE**, and **Window Function** combined into a single query block:

```sql
WITH AggregatedCustomerSales AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT 
    c.Customer_Name,
    ROUND(acs.Total_Sales, 2) AS Total_Sales,
    RANK() OVER (ORDER BY acs.Total_Sales DESC) AS Rank
FROM AggregatedCustomerSales acs
JOIN customers c ON acs.Customer_ID = c.Customer_ID
ORDER BY Rank ASC;

```

---

## 🏆 Mini Project: Customer Sales Insights & Verified Results

### Q1: Who are the top 5 customers?

```sql
WITH CustomerSalesTotals AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales FROM orders GROUP BY Customer_ID
)
SELECT TOP 5 c.Customer_Name, ROUND(cs.Total_Sales, 2) AS Total_Lifetime_Sales
FROM CustomerSalesTotals cs JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Total_Lifetime_Sales DESC;

```

* **Sean Miller** ($25,043.05) — *Rank 1*
* **Tamara Chand** ($19,052.22) — *Rank 2*
* **Raymond Buch** ($15,117.34) — *Rank 3*
* **Tom Ashbrook** ($14,595.62) — *Rank 4*
* **Adrian Barton** ($14,473.57) — *Rank 5*

### Q2: Who are the bottom 5 customers?

```sql
WITH CustomerSalesTotals AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales FROM orders GROUP BY Customer_ID
)
SELECT TOP 5 c.Customer_Name, ROUND(cs.Total_Sales, 2) AS Total_Lifetime_Sales
FROM CustomerSalesTotals cs JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Total_Lifetime_Sales ASC;

```

* **Thais Sissman** ($4.83) — *Rank 793*
* **Lela Donovan** ($5.30) — *Rank 792*
* **Carl Jackson** ($16.52) — *Rank 791*
* **Mitch Gastineau** ($16.74) — *Rank 790*
* **Roy Skaria** ($22.33) — *Rank 789*

### Q3: Which customers made only one order?

```sql
SELECT c.Customer_Name, c.Segment, COUNT(DISTINCT o.Order_ID) AS Distinct_Order_Count, ROUND(SUM(o.Sales), 2) AS Total_Sales
FROM orders o JOIN customers c ON o.Customer_ID = c.Customer_ID
GROUP BY c.Customer_ID, c.Customer_Name, c.Segment
HAVING COUNT(DISTINCT o.Order_ID) = 1
ORDER BY Total_Sales DESC;

```

* Exactly **12 unique customers** placed only a single order during their lifecycle. High-value profiles in this segment include:
* *Jenna Caffey* (1 Order, $1,058.11)
* *Susan MacKendrick* (1 Order, $1,043.04)
* *Theresa Coyne* (1 Order, $1,038.26)



### Q4: Which customers have above-average sales?

*Matches accounts crossing the calculated customer spending baseline ($\approx \$2,896.85$).*

* Exactly **294 out of 793 total unique customer records** ($\approx 37\%$) generated above-average lifetime sales metrics.

### Q5: What is the highest order value per customer?

* **Sean Miller** generated the absolute highest single order total recorded across the entire platform via order ID `CA-2014-145317`, valued at a massive **$23,661.23**.

---

## 💡 Executive Strategic Observations

1. **High Revenue Concentration:** Since only 37% of customer profiles maintain a gross purchase value above the baseline mean, your cash flow relies heavily on a high-value core tier. Loyalty programs and premium customer account parameters should be focused around protecting this specific segment.
2. **Leaky Customer Acquisition Funnel:** The 12 single-order customers represent immediate re-engagement opportunities. Customers like *Jenna Caffey* and *Susan MacKendrick* registered high-ticket baskets exceeding $1,000 on their first checkout but never returned. This highlights a clear drop-off in post-purchase retention efforts. Target these 12 accounts directly with automated win-back marketing funnels.
3. **Acquisition Spend Optimization:** Customers at the absolute bottom tier, such as *Thais Sissman* ($4.83 lifetime spend), likely cost the business more to acquire than they generated. Marketing teams should trace these low-yield accounts back to their original referral or ad channels to minimize budget leakage on low-intent buyers and optimize long-term Customer Acquisition Cost (CAC).

```

```
