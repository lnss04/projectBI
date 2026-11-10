-- =====================================================================
--  TEST UNIQUEMENT : mini-copie de dellstore (même schéma que slide 97)
--  pour tester le flux chez soi dans Docker. À NE PAS lancer à l'école.
-- =====================================================================
IF DB_ID('dellstore') IS NULL CREATE DATABASE dellstore;
GO
USE dellstore;
GO
DROP TABLE IF EXISTS hist_orderlines, hist_orders, hist_customers, hist_products, orderlines, orders, inventory, products, categories, customers;
GO
CREATE TABLE categories (category INT PRIMARY KEY, categoryname VARCHAR(50) NOT NULL);
CREATE TABLE products (prod_id INT PRIMARY KEY, category INT NOT NULL, title VARCHAR(50) NOT NULL, actor VARCHAR(50) NOT NULL,
                       price NUMERIC(12,2) NOT NULL, special SMALLINT, common_prod_id INT NOT NULL);
CREATE TABLE inventory (prod_id INT PRIMARY KEY, quan_in_stock INT NOT NULL, sales INT NOT NULL);
CREATE TABLE customers (customerid INT PRIMARY KEY, firstname VARCHAR(50) NOT NULL, lastname VARCHAR(50) NOT NULL,
  address1 VARCHAR(50) NOT NULL, address2 VARCHAR(50), city VARCHAR(50) NOT NULL, state VARCHAR(50), zip INT,
  country VARCHAR(50) NOT NULL, region SMALLINT NOT NULL, email VARCHAR(50), phone VARCHAR(50), creditcardtype INT NOT NULL,
  creditcard VARCHAR(50) NOT NULL, creditcardexpiration VARCHAR(50) NOT NULL, username VARCHAR(50) NOT NULL,
  pwd VARCHAR(50) NOT NULL, age SMALLINT, income INT, gender VARCHAR(1));
CREATE TABLE orders (orderid INT PRIMARY KEY, orderdate DATE NOT NULL, customerid INT, netamount NUMERIC(12,2) NOT NULL,
                     tax NUMERIC(12,2) NOT NULL, totalamount NUMERIC(12,2) NOT NULL);
CREATE TABLE orderlines (orderlineid SMALLINT NOT NULL, orderid INT NOT NULL, prod_id INT NOT NULL, quantity SMALLINT NOT NULL,
                         orderdate DATE NOT NULL, PRIMARY KEY (orderid, orderlineid));
CREATE TABLE hist_customers  (customerid INT PRIMARY KEY, last_update DATETIME2(3) NOT NULL);
CREATE TABLE hist_orders     (orderid INT PRIMARY KEY, last_update DATETIME2(3) NOT NULL);
CREATE TABLE hist_orderlines (orderid INT NOT NULL, orderlineid SMALLINT NOT NULL, last_update DATETIME2(3) NOT NULL, PRIMARY KEY (orderid, orderlineid));
CREATE TABLE hist_products   (prod_id INT PRIMARY KEY, last_update DATETIME2(3) NOT NULL);
GO
INSERT INTO categories VALUES (1,'Action'),(2,'Animation'),(3,'Children'),(4,'Classics'),(5,'Comedy'),(6,'Documentary'),
 (7,'Drama'),(8,'Family'),(9,'Foreign'),(10,'Games'),(11,'Horror'),(12,'Music'),(13,'New'),(14,'Sci-Fi'),(15,'Sports'),(16,'Travel');

WITH n AS (SELECT TOP (60) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects)
INSERT INTO products
SELECT i, 1 + (i % 16), CONCAT('DVD TITLE ', i), CONCAT('ACTOR ', i % 13), 9.99 + (i % 21), i % 2, i
FROM n;

-- clients US (region 1, state renseigné) et "reste du monde" (region 2, state vide) ; villes = chaînes aléatoires comme dans la vraie dellstore
WITH n AS (SELECT TOP (40) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects)
INSERT INTO customers
SELECT i, CONCAT('FN', i), CONCAT('LN', i), CONCAT(i, ' Dell Way'), NULL,
       CONCAT('CITY', CHAR(65 + i % 26), CHAR(65 + (i * 7) % 26)),
       CASE WHEN i % 2 = 0 THEN (CASE i % 5 WHEN 0 THEN 'TX' WHEN 1 THEN 'CA' WHEN 2 THEN 'NY' WHEN 3 THEN 'FL' ELSE 'WA' END) ELSE '' END,
       10000 + i,
       CASE WHEN i % 2 = 0 THEN 'US' ELSE (CASE i % 7 WHEN 0 THEN 'Australia' WHEN 1 THEN 'Canada' WHEN 2 THEN 'Chile'
                                                       WHEN 3 THEN 'China' WHEN 4 THEN 'France' WHEN 5 THEN 'Germany' ELSE 'UK' END) END,
       CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END,
       CONCAT('user', i, '@dell.com'), '0000000000', 1, '1234567812345678', '2030/12', CONCAT('user', i), 'password', 30, 50000, 'M'
FROM n;

WITH n AS (SELECT TOP (200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects)
INSERT INTO orders
SELECT i, DATEADD(DAY, i * 3, '2004-01-01'), 1 + (i % 40), 0, 0, 0 FROM n;

WITH n AS (SELECT TOP (3) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS l FROM sys.all_objects)
INSERT INTO orderlines
SELECT n.l, o.orderid, 1 + ((o.orderid * 7 + n.l * 11) % 60), 1 + ((o.orderid + n.l) % 3), o.orderdate
FROM orders o CROSS JOIN n
WHERE n.l <= 1 + (o.orderid % 3);

-- netamount / tax / total cohérents avec les lignes
UPDATE o SET netamount = x.net, tax = ROUND(x.net * 0.0825, 2), totalamount = x.net + ROUND(x.net * 0.0825, 2)
FROM orders o JOIN (SELECT ol.orderid, SUM(ol.quantity * p.price) AS net FROM orderlines ol JOIN products p ON p.prod_id = ol.prod_id GROUP BY ol.orderid) x
  ON x.orderid = o.orderid;

INSERT INTO inventory SELECT prod_id, 100, 0 FROM products;
INSERT INTO hist_customers  SELECT customerid, '2024-01-01' FROM customers;
INSERT INTO hist_orders     SELECT orderid, '2024-01-01' FROM orders;
INSERT INTO hist_orderlines SELECT orderid, orderlineid, '2024-01-01' FROM orderlines;
INSERT INTO hist_products   SELECT prod_id, '2024-01-01' FROM products;
GO
SELECT (SELECT COUNT(*) FROM customers) AS customers, (SELECT COUNT(*) FROM orders) AS orders, (SELECT COUNT(*) FROM orderlines) AS orderlines;
