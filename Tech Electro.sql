-- Preliminaries -creation of Schema/Database
CREATE SCHEMA tech_electro;
USE tech_electro;


-- DATA EXPLORATION
SELECT * FROM Sales_data LIMIT 5;
SELECT * FROM External_Factors LIMIT 5;
SELECT * FROM Product_data LIMIT 5;

-- Understanding the structure of the datasets
SHOW COLUMNS FROM External_Factors;
DESC Product_data;
DESC Sales_data;


-- DATA CLEANING
-- changing to the right data type for all columns
-- external factors table
-- SalesDate DATE, GDP DECIMAL(5,2), SeasonalFactor DECIMAL(5,2)
ALTER TABLE External_Factors
ADD COLUMN New_Sales_Date DATE;
SET SQL_SAFE_UPDATES = 0; -- turning off safe updates
UPDATE External_Factors  
SET New_Sales_Date = STR_TO_DATE(`Sales Date`, '%d/%m/%Y');
ALTER TABLE External_Factors
DROP COLUMN `Sales Date`;
ALTER TABLE External_Factors
CHANGE COLUMN New_Sales_Date Sales_Date DATE;

ALTER TABLE External_Factors
MODIFY COLUMN GDP DECIMAL(15, 2);

ALTER TABLE External_Factors
MODIFY COLUMN `Inflation Rate` DECIMAL(15, 2);

SHOW COLUMNS FROM External_Factors;

-- Product
-- Product_ID INT NOT NULL, Product_Category TEXT, Promotions ENUM('yes', 'no')
ALTER TABLE Product_data
ADD COLUMN NewPromotions ENUM('yes', 'no'); 
UPDATE Product_data
SET NewPromotions = CASE
	WHEN Promotions = 'yes' THEN 'yes'
    WHEN Promotions = 'no' THEN 'no'
    ELSE NULL
END;
ALTER TABLE Product_data
DROP COLUMN Promotions;
ALTER TABLE Product_data
CHANGE COLUMN NewPromotions Promotions ENUM('yes', 'no');

DESC Product_data;

-- Sales data
-- Product ID INT NOT NULL, Sales_Date DATE, Inventory_Quantity INT, Product Cost DECIMAL(10,2)
ALTER TABLE Sales_data
ADD COLUMN New_Sales_Date DATE;
UPDATE Sales_data
SET New_Sales_Date = STR_TO_DATE(`Sales Date`, '%d/%m/%Y');
ALTER TABLE Sales_data
DROP COLUMN `Sales Date`;
ALTER TABLE External_Factors
CHANGE COLUMN New_Sales_Date Sales_Date DATE;
DESC Sales_data;

-- Identify missing values using `IS NULL` function
-- external factor
SELECT
SUM(CASE WHEN Sales_Date IS NULL THEN 1 ELSE 0 END) AS missing_sales_date,
SUM(CASE WHEN GDP IS NULL THEN 1 ELSE 0 END) AS missing_gdp,
SUM(CASE WHEN `Inflation Rate` IS NULL THEN 1 ELSE 0 END) AS missing_inflation_rate,
SUM(CASE WHEN `Seasonal Factor` IS NULL THEN 1 ELSE 0 END) AS missing_seasonal_factor
FROM External_Factors;

-- Product_data
SELECT
SUM(CASE WHEN `Product ID` IS NULL THEN 1 ELSE 0 END) AS missing_product_id,
SUM(CASE WHEN `Product Category` IS NULL THEN 1 ELSE 0 END) AS missing_product_category,
SUM(CASE WHEN Promotions IS NULL THEN 1 ELSE 0 END) AS missing_promotions
FROM Product_data;

-- sales_data;
SELECT
SUM(CASE WHEN `Product ID` IS NULL THEN 1 ELSE 0 END) AS missing_product_id,
SUM(CASE WHEN Sales_Date IS NULL THEN 1 ELSE 0 END) AS missing_sales_date,
SUM(CASE WHEN `Inventory Quantity` IS NULL THEN 1 ELSE 0 END) AS missing_inventory_quantity,
SUM(CASE WHEN `Product Cost` IS NULL THEN 1 ELSE 0 END) AS missing_product_cost
FROM Sales_data;

-- Check for duplicates using 'GROUP BY' and 'HAVING' clauses and remove them if necessary
-- External Factors
SELECT Sales_Date, COUNT(*) AS count
FROM External_Factors
GROUP BY Sales_Date
HAVING count > 1;

SELECT COUNT(*) FROM (SELECT Sales_Date, COUNT(*) AS count
FROM External_Factors
GROUP BY Sales_Date
HAVING count > 1) AS dup;

-- Product_data
SELECT `Product ID`, COUNT(*) AS count
FROM Product_data
GROUP BY `Product ID`
HAVING count > 1;

-- Sales_data
SELECT `Product ID`, Sales_date, COUNT(*) AS count
FROM Sales_data
GROUP BY `Product ID`,Sales_date
HAVING count > 1;

-- Dealing with duplicates for External_Factors and Products_data
-- external factors
DELETE e1 FROM External_Factors e1
INNER JOIN (
	SELECT Sales_Date,
ROW_NUMBER() OVER (PARTITION BY Sales_Date ORDER BY Sales_Date) AS rn
FROM External_Factors
) e2 ON e1.Sales_Date = e2.Sales_Date
WHERE e2.rn > 1;

-- Product_data
DELETE p1 FROM product_data p1
INNER JOIN (
	SELECT `Product ID`,
    ROW_NUMBER() OVER (PARTITION BY `Product ID` ORDER BY `Product ID`) AS rn
    FROM Product_data
    ) p2 ON p1.`Product ID` = p2.`Product ID`
    WHERE p2.rn > 1;
    
-- DATA INTEGRATION 
-- Sales_data and Product_data first
CREATE VIEW sales_product_data AS
SELECT
s.`Product ID`,
S. Sales_Date,
s.`Inventory Quantity`,
s. `Product Cost`,
p. `Product Category`,
p. Promotions
FROM sales_data s
JOIN Product_data p ON s.`Product ID` = p.`Product ID`;

-- sale_product_data and External_Factors
CREATE VIEW Inventory_data AS
SELECT
sp.`Product ID`,
sp. Sales_Date,
sp.`Inventory Quantity`,
sp. `Product Cost`,
sp. `Product Category`,
sp. Promotions,
e.GDP,
e.`Inflation Rate`,
e.`Seasonal Factor`
FROM sales_product_data sp
LEFT JOIN External_Factors e
ON sp.Sales_Date = e.Sales_Date;

-- DESCRIPTIVE ANALYSIS
-- Basic Statistics;
-- Average sales (calculated as the product of "Inventory Quantity" and "Product Cost").
SELECT `Product ID`,
AVG(`Inventory Quantity` * `Product Cost`) AS avg_sales
FROM Inventory_data
GROUP BY `Product ID`
ORDER BY avg_sales DESC;

-- Median stock levels (i.e.,"Inventory Quantity").
SELECT `Product ID`, AVG(`Inventory Quantity`) AS median_stock
FROM (
 SELECT `Product ID`,
		`Inventory Quantity`,
ROW_NUMBER() OVER(PARTITION BY `Product ID` ORDER BY `Inventory Quantity`) AS row_num_asc,
ROW_NUMBER() OVER(PARTITION BY `Product ID` ORDER BY `Inventory Quantity`) AS row_num_desc
 FROM Inventory_data
) AS subquery
WHERE row_num_asc IN (row_num_desc,row_num_desc - 1, row_num_desc + 1)
GROUP BY `Product ID`;

-- Product performance metrics (total sales per product). 
SELECT `Product ID`,
 ROUND(SUM(`Inventory Quantity` * `Product Cost`)) AS total_sales
FROM Inventory_data
GROUP BY `Product ID`
ORDER BY total_sales DESC;

-- Identifying high-demand products based on average sales
WITH HighDemandProducts AS (
SELECT `Product ID`, AVG(`Inventory Quantity`) as avg_sales
 FROM Inventory_data
 GROUP BY `Product ID`
HAVING avg_sales > (
SELECT AVG(`Inventory Quantity`) * 0.95 FROM Sales_data
	)
)
-- Calculate stockout frequency for high-demand products
SELECT s.`Product ID`,
COUNT(*) as stockout_frequency
FROM Inventory_data s
WHERE s.`Product ID` IN (SELECT `Product ID` FROM HighDemandProducts)
AND s.`Inventory Quantity` = 0
GROUP BY s.`Product ID`;
 
-- INFLUENCE OF EXTERNAL FACTORS
-- GDP
SELECT `Product ID`,
AVG(CASE WHEN `GDP` > 0 THEN `Inventory Quantity` ELSE NULL END) AS avg_sales_positive_gdp,
AVG(CASE WHEN `GDP` <= 0 THEN `Inventory Quantity` ELSE NULL END) AS avg_sales_non_positive_gdp
FROM Inventory_data
GROUP BY `Product ID`
HAVING avg_sales_positive_gdp IS NOT NULL;

-- Inflation
SELECT `Product ID`,
AVG(CASE WHEN `Inflation Rate` > 0 THEN `Inventory Quantity` ELSE NULL END) AS avg_sales_positive_inflation,
AVG(CASE WHEN `Inflation Rate` <= 0 THEN `Inventory Quantity` ELSE NULL END) AS avg_sales_non_positive_inflation
FROM Inventory_data
GROUP BY `Product ID`
HAVING avg_sales_positive_inflation IS NOT NULL;

-- INVENTORY OPTIMIZATION
-- Determination of the optimal reorder point for each product based on historical sales data and external factors. 
-- Reorder Point = Lead Time Demand + Safety Stock
-- Lead Time Demand = Rolling Average Sales x Lead Time
-- Reorder Point = Rolling Average Sales * Lead Time  + (Z x Lead Time^-2 x Standard Deviation of Demand)
-- Safety Stock = Z x Lead Time^-2 x Standard Deviation of Demand 
-- Z = 1.645
-- A constant lead time of 7 days for all products
-- Target of 95% service level.

WITH InventoryCalculations AS (
 SELECT `Product ID`,
 AVG(rolling_avg_sales) as avg_rolling_sales,
 AVG(rolling_variance) as avg_rolling_variance
FROM (
SELECT `Product ID`,
AVG(daily_sales) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_avg_sales,
AVG(squared_diff) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_variance
FROM (
SELECT `Product ID`,
 Sales_Date,`Inventory Quantity` * `Product Cost` as daily_sales,
 (`Inventory Quantity` * `Product Cost` - AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `PRODUCT ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW))
 * (`Inventory Quantity` * `Product Cost` - AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `PRODUCT ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)) as squared_diff
FROM Inventory_data
) subquery
 ) subquery2
   GROUP BY `Product ID`
)
SELECT `Product ID`,
avg_rolling_sales * 7 as lead_time_demand,
  1.645 * (avg_rolling_variance * 7) as safety_stock,
(avg_rolling_sales * 7) + (1.645 * (avg_rolling_variance * 7)) as reorder_point
FROM InventoryCalculations;

-- Create the inventory_optimization table
CREATE TABLE inventory_optimization(
	`Product id` INT,
Reorder_Point DOUBLE
);

-- Step 2: Create the Stored Procedure to Recalculate Reorder Point

DELIMITER //
CREATE PROCEDURE RecalculateReorderPoint(productID INT)
BEGIN 
	DECLARE avgRollingSales DOUBLE;
    DECLARE avgRollingVariance DOUBLE;
    DECLARE leadTimeDemand DOUBLE;
    DECLARE safetyStock DOUBLE;
    DECLARE reorderPoint DOUBLE;
   SELECT AVG(rolling_avg_sales), AVG(rolling_variance)
   INTO avgrollingSales, avgRollingVariance
FROM (
SELECT `Product ID`, 
AVG(daily_sales) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_avg_sales,
AVG(squared_diff) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_variance
FROM (
SELECT `Product ID`,
 Sales_Date,`Inventory Quantity` * `Product Cost` as daily_sales,
 (`Inventory Quantity` * `Product Cost` - AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `PRODUCT ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW))
 * (`Inventory Quantity` * `Product Cost` - AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `PRODUCT ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)) as squared_diff
FROM Inventory_data
) InnerDerived
 ) OuterDerived;
SET leadTimeDemand = avgRollingSales * 7;
SET safetyStock = 1.645 * SQRT(avgRollingVariance *7);
SET reorderPoint = leadTimeDemand + safetyStock;
   
INSERT INTO inventory_optimization(`Product ID`, Reorder_Point)
VALUES (productID,reorderPoint)
ON DUPLICATE KEY UPDATE Reorder_Point = reorderPoint;
END //
DELIMITER ;

-- Step 3: make inventory_data a permanent table
CREATE TABLE Inventory_table AS SELECT * FROM Inventory_data;
-- Step 4: Create the Trigger
DELIMITER //
CREATE TRIGGER AfterInsertUnifiedTable
AFTER INSERT ON Inventory_table
FOR EACH ROW
BEGIN
 CALL RecalculateReorderPoint(NEW.`Product ID`);
 END //
 DELIMITER ;
 
 -- OVERSTOCKING AND UNDERSTOCKING
 WITH RollingSales AS (
 SELECT `Product ID`,
 Sales_Date,
 AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_avg_sales
  FROM inventory_table
  ),
  -- Calculate the number of days a product was out of stock
  StockoutDays AS(
  SELECT `Product ID`,
  COUNT(*) as stockout_days
  FROM inventory_table
  WHERE `Inventory Quantity` = 0
  GROUP BY `Product ID`
  )
  -- Join the above CTEs with the main table to get the results
  SELECT f.`Product ID`,
  AVG(f.`Inventory Quantity` * f.`Product Cost`) as avg_inventory_value,
  AVG(rs.rolling_avg_sales) as avg_rolling_sales,
   COALESCE(sd.stockout_days, 0) as stockout_days
  FROM inventory_table f
  JOIN RollingSales rs ON f.`Product ID` = rs.`Product ID` AND f.Sales_Date = rs.Sales_Date
  LEFT JOIN StockoutDays sd ON f.`Product ID` = sd.`Product ID`
  GROUP BY f.`Product ID`, sd.stockout_days;
  
  
  -- MONITOR AND ADJUST 
	-- Monitor inventory levels
    DELIMITER //
CREATE PROCEDURE MonitorInventoryLevels()
BEGIN
SELECT `Product ID`, AVG(`Inventory Quantity`) as AvgInventory
FROM Inventory_table
GROUP BY `Product ID`
ORDER BY AvgInventory DESC;
END //
DELIMITER ;
  
-- Monitor Sales Trends
DELIMITER //
CREATE PROCEDURE MonitorSalesTrends()
BEGIN
SELECT `Product ID`,Sales_Date,
AVG(`Inventory Quantity` * `Product Cost`) OVER (PARTITION BY `Product ID` ORDER BY Sales_Date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as RollingAvgSales
	FROM inventory_table
	 ORDER BY `Product id`, Sales_Date;
END//
DELIMITER ; 

-- Monitor Stockout frequencies
DELIMITER //
CREATE PROCEDURE MonitorStockouts()
BEGIN
SELECT `Product ID`, COUNT(*) as StockoutDays
FROM inventory_table
 WHERE `Inventory Quantity` = 0
GROUP BY `Prouct ID`
ORDER BY StockoutDays DESC;
END//
DELIMITER ; 


-- FEEDBACK LOOP

-- Feedback loop Establishment;
 -- Feedback Portal: Develop an online platform for stakeholders to easily submit feedback on inventory performance and challenges.
 -- Review Meetings: Organize periodic sessions to discuss inventory system performance and gather direct insights.
 -- System Monitoring: Use established SQL procedures to track system metrics, with deviations from expectations flagged for review.

-- Refinement Based on Feedback;
-- Feedback Analysis: Regularly compile and scrutinize feedback to identify recurring themes or pressing issues.
-- Action Implementation: Prioritize and act on the feedback to adjust reorder points, safety stock levels, or overall processes.
-- Change Communication: Inform stakeholders about changes, underscoring the value of their feedback and ensuring transparency.

-- General Insights;

-- Inventory Discrepancies: The initial stages of the analysis revealed significant discrepancies in inventory levels, with instances of both overstocking and understocking.
  -- These inconsistencies were contributing to capital inefficiencies and customers dissatisfaction.

-- Sales Trends and External Influences: The analysis indicated that sales trends were notably influenced by various external factors.
 -- Recognizing these patterns provides an opportunity to forecast demand more accurately.
 
 -- Suboptimal Inventory Levels: Through the inventory optimization analysis, it was evident that the existing inventory levels were not optimized for current sales trends.
  -- They were cases where products were produced in excess.
  
  
  -- Recommendations;
  
  -- 1. Implementation of Dynamic Inventory Management: The company should transition from a static to a dynamic inventory management system,
  -- adjusting inventory levels based on real-time sales trends, seasonality and external factors. 
  
  -- 2. Optimize Reorder Points and Safety Stocks: Utilize the reorder points and safety stocks calculated during the analysis to minimize stockouts and reduce excess inventory.
  -- Regularly review these metrics to ensure they align with current market conditions.
  
  -- 3. Enhance Pricing Strategies: Conduct a thorough review of product pricing strategies, especially for products identified as unprofitable.
  -- Consider factors such as competitor pricing, market demand, and product acquisition costs.
  
  -- 4. Reduce Overstock: Identify products that are cosistently overstocked and take steps to reduce their inventory levels.
  -- This could include promotional sales, discounts, or even discontinuing products with low sales performance.

  -- 5. Establish a Feedback loop: Develop a systematic approach to collect and analyse feedback from various stakeholders.
  -- Use this feedback for continuous improvement and alignment with business objectives.
  
  -- 6.Regular Monitoring and Adjustments: Adopt a proactive approach to inventory management by regularly monitoring key metrics
  -- and making necessary adjustments to inventory levels, order quantities, and safety stocks.


  


 
    
    


