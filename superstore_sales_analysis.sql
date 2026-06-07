-- STEP 1 : Creating Tables in SQL Server (T-SQL)

-- Drop tables if they already exist to ensure a clean slate
IF OBJECT_ID('dbo.orders', 'U') IS NOT NULL DROP TABLE dbo.orders;
IF OBJECT_ID('dbo.customers', 'U') IS NOT NULL DROP TABLE dbo.customers;
IF OBJECT_ID('dbo.products', 'U') IS NOT NULL DROP TABLE dbo.products;

-- Create customers table
CREATE TABLE customers (
    Customer_ID VARCHAR(50) PRIMARY KEY,
    Customer_Name VARCHAR(100),
    Segment VARCHAR(50)
);

-- Create products table
CREATE TABLE products (
    Product_ID VARCHAR(50) PRIMARY KEY,
    Category VARCHAR(50),
    Sub_Category VARCHAR(50),
    Product_Name VARCHAR(255)
);

-- Create orders table
CREATE TABLE orders (
    Row_ID INT PRIMARY KEY,
    Order_ID VARCHAR(50),
    Order_Date VARCHAR(50),  
    Ship_Date VARCHAR(50),   
    Ship_Mode VARCHAR(50),
    Customer_ID VARCHAR(50),
    Product_ID VARCHAR(50),
    Sales FLOAT,
    Quantity INT,
    Discount FLOAT,
    Profit FLOAT,
    City VARCHAR(100),
    State VARCHAR(100),
    Country VARCHAR(100),
    Postal_Code VARCHAR(50),
    Region VARCHAR(50),
    FOREIGN KEY (Customer_ID) REFERENCES customers(Customer_ID),
    FOREIGN KEY (Product_ID) REFERENCES products(Product_ID)
);

-- STEP 2: Inserting Data 
-- Since the customer data is perfectly clean, SELECT DISTINCT works flawlessly.
INSERT INTO customers (Customer_ID, Customer_Name, Segment)
SELECT DISTINCT 
    Customer_ID, 
    Customer_Name, 
    Segment
FROM superstore_raw;

-- To prevent Primary Key violation from mismatched product names, 
-- we use ROW_NUMBER() to select exactly one row per unique Product_ID.
INSERT INTO products (Product_ID, Category, Sub_Category, Product_Name)
SELECT 
    Product_ID, 
    Category, 
    Sub_Category, 
    Product_Name
FROM (
    SELECT 
        Product_ID, 
        Category, 
        Sub_Category, 
        Product_Name, 
        ROW_NUMBER() OVER (PARTITION BY Product_ID ORDER BY Row_ID DESC) as rn
    FROM superstore_raw
) AS prod_src
WHERE rn = 1;

-- This table holds every transaction row line-item, so we select all records.
INSERT INTO orders (
    Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode, 
    Customer_ID, Product_ID, Sales, Quantity, Discount, Profit, 
    City, State, Country, Postal_Code, Region
)
SELECT 
    Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode, 
    Customer_ID, Product_ID, Sales, Quantity, Discount, Profit, 
    City, State, Country, Postal_Code, Region
FROM superstore_raw;

-- STEP 3: Apply Subqueries to Filter Data.
-- Above average sales orders are selected and ordered by sales in descending order.
SELECT 
    Row_ID, 
    Order_ID, 
    Customer_ID, 
    Sales
FROM orders
WHERE Sales > (SELECT AVG(Sales) FROM orders)
ORDER BY Sales DESC;

-- Highest order value per customer
SELECT 
    o1.Customer_ID, 
    o1.Order_ID, 
    SUM(o1.Sales) AS Highest_Order_Sales
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

-- STEP 4: Common Table Expression (CTE) for Customer Sales Aggregations
-- 1. Define the CTE using the 'WITH' keyword
WITH CustomerSalesTotals AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales,
        COUNT(DISTINCT Order_ID) AS Total_Orders,
        SUM(Quantity) AS Total_Items_Bought
    FROM orders
    GROUP BY Customer_ID
)

-- 2. Query immediately from the CTE below
SELECT 
    c.Customer_ID,
    c.Customer_Name,
    c.Segment,
    ROUND(cs.Total_Sales, 2) AS Cumulative_Sales,
    cs.Total_Orders,
    cs.Total_Items_Bought
FROM CustomerSalesTotals cs
JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Cumulative_Sales DESC;

-- STEP 5: Window Functions for Ranking and Analysis

WITH CustomerSalesTotals AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT 
    c.Customer_Name,
    c.Segment,
    ROUND(cs.Total_Sales, 2) AS Cumulative_Sales,
    
    -- 1. ROW_NUMBER gives a strict 1, 2, 3, 4 sequentially
    ROW_NUMBER() OVER (ORDER BY cs.Total_Sales DESC) AS Sales_Row_Number,
    
    -- 2. RANK gives the same number for ties, skipping subsequent ranks
    RANK() OVER (ORDER BY cs.Total_Sales DESC) AS Sales_Rank

FROM CustomerSalesTotals cs
JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Sales_Rank ASC;

-- STEP 6: Combined Analytical Query (CTE + JOIN + Window Function)
-- 1. Create the Common Table Expression to aggregate raw transactional sales
WITH AggregatedCustomerSales AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)

-- 2. Execute primary query joining dimensions and applying window functions
SELECT 
    c.Customer_Name,
    ROUND(acs.Total_Sales, 2) AS Total_Sales,
    RANK() OVER (ORDER BY acs.Total_Sales DESC) AS Sales_Rank
FROM AggregatedCustomerSales acs
JOIN customers c ON acs.Customer_ID = c.Customer_ID
ORDER BY Sales_Rank ASC;

-- STEP 7: Solving Core Business Queries with Advanced Analytics

-- BUSINESS QUERY 1: Top 5 High-Value Customers by Total Lifetime Sales
WITH CustomerSalesTotals AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT TOP 5 
    c.Customer_Name, 
    c.Segment,
    ROUND(cs.Total_Sales, 2) AS Total_Lifetime_Sales,
    RANK() OVER (ORDER BY cs.Total_Sales DESC) as Sales_Rank
FROM CustomerSalesTotals cs
JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Total_Lifetime_Sales DESC;

-- BUSINESS QUERY 2: Low-Yield Customers (Bottom 5 by Total Lifetime Sales)
WITH CustomerSalesTotals AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT TOP 5 
    c.Customer_Name, 
    c.Segment,
    ROUND(cs.Total_Sales, 2) AS Total_Lifetime_Sales,
    RANK() OVER (ORDER BY cs.Total_Sales ASC) as Sales_Rank
FROM CustomerSalesTotals cs
JOIN customers c ON cs.Customer_ID = c.Customer_ID
ORDER BY Total_Lifetime_Sales ASC;

-- BUSINESS QUERY 3: Single-Order Customers 
SELECT 
    c.Customer_Name, 
    c.Segment, 
    COUNT(DISTINCT o.Order_ID) AS Distinct_Order_Count, 
    ROUND(SUM(o.Sales), 2) AS Total_Sales
FROM orders o
JOIN customers c ON o.Customer_ID = c.Customer_ID
GROUP BY c.Customer_ID, c.Customer_Name, c.Segment
HAVING COUNT(DISTINCT o.Order_ID) = 1
ORDER BY Total_Sales DESC;

-- BUSINESS QUERY 4: Customer-Level Above-Average Sales Performance
WITH CustomerSalesTotals AS (
    SELECT 
        Customer_ID, 
        SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT 
    c.Customer_Name, 
    ROUND(cs.Total_Sales, 2) AS Total_Lifetime_Sales
FROM CustomerSalesTotals cs
JOIN customers c ON cs.Customer_ID = c.Customer_ID
WHERE cs.Total_Sales > (
    SELECT AVG(Total_Sales) 
    FROM CustomerSalesTotals
)
ORDER BY cs.Total_Sales DESC;

-- ADDITIONS FOR TASK 2 SPECIFICATIONS
-- 1. FROM STEP 2, QUERY 4: Find customers whose total sales are above average (CTE + Subquery)
WITH CustomerSales AS (
    SELECT Customer_ID, SUM(Sales) AS Total_Sales
    FROM orders
    GROUP BY Customer_ID
)
SELECT Customer_ID, ROUND(Total_Sales, 2) AS Above_Avg_Customer_Sales
FROM CustomerSales
WHERE Total_Sales > (SELECT AVG(Total_Sales) FROM CustomerSales)
ORDER BY Above_Avg_Customer_Sales DESC;


-- 2. FROM STEP 2, QUERY 6: Assign row numbers to each order within a customer. 
SELECT 
    Customer_ID, 
    Order_ID, 
    Order_Date, 
    Sales,
    ROW_NUMBER() OVER (
        PARTITION BY Customer_ID 
        ORDER BY Order_Date DESC, Order_ID ASC
    ) AS Order_Row_Num
FROM orders;


-- 3. FROM STEP 2, QUERY 7: Display top 3 customers based on total sales. (Window Function)
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