-- =====================================================================
--  TEST UNIQUEMENT : mini-copie de classicmodels (même schéma que slide 96)
--  pour tester le flux chez soi dans Docker. À NE PAS lancer à l'école.
-- =====================================================================
DROP TABLE IF EXISTS orderdetails, orders, payments, customers, employees, offices, products, productlines CASCADE;

CREATE TABLE productlines (productline VARCHAR(50) PRIMARY KEY, textdescription VARCHAR(4000));
CREATE TABLE products (
  productcode VARCHAR(15) PRIMARY KEY, productname VARCHAR(70) NOT NULL, productline VARCHAR(50) NOT NULL REFERENCES productlines,
  productscale VARCHAR(10) NOT NULL, productvendor VARCHAR(50) NOT NULL, productdescription TEXT NOT NULL,
  quantityinstock INT NOT NULL, buyprice DECIMAL(10,2) NOT NULL, msrp DECIMAL(10,2) NOT NULL, last_update TIMESTAMP);
CREATE TABLE offices (
  officecode VARCHAR(10) PRIMARY KEY, city VARCHAR(50) NOT NULL, phone VARCHAR(50) NOT NULL, addressline1 VARCHAR(50) NOT NULL,
  addressline2 VARCHAR(50), state VARCHAR(50), country VARCHAR(50) NOT NULL, postalcode VARCHAR(15) NOT NULL, territory VARCHAR(10) NOT NULL);
CREATE TABLE employees (
  employeenumber INT PRIMARY KEY, lastname VARCHAR(50) NOT NULL, firstname VARCHAR(50) NOT NULL, extension VARCHAR(10) NOT NULL,
  email VARCHAR(100) NOT NULL, officecode VARCHAR(10) NOT NULL REFERENCES offices, reportsto INT, jobtitle VARCHAR(50) NOT NULL);
CREATE TABLE customers (
  customernumber INT PRIMARY KEY, customername VARCHAR(50) NOT NULL, contactlastname VARCHAR(50) NOT NULL, contactfirstname VARCHAR(50) NOT NULL,
  phone VARCHAR(50) NOT NULL, addressline1 VARCHAR(50) NOT NULL, addressline2 VARCHAR(50), city VARCHAR(50) NOT NULL, state VARCHAR(50),
  postalcode VARCHAR(15), country VARCHAR(50) NOT NULL, salesrepemployeenumber INT, creditlimit DECIMAL(10,2), last_update TIMESTAMP);
CREATE TABLE payments (customernumber INT NOT NULL, checknumber VARCHAR(50) NOT NULL, paymentdate DATE NOT NULL, amount NUMERIC(10,2) NOT NULL,
  PRIMARY KEY (customernumber, checknumber));
CREATE TABLE orders (
  ordernumber INT PRIMARY KEY, orderdate DATE NOT NULL, requireddate DATE NOT NULL, shippeddate DATE, status VARCHAR(15) NOT NULL,
  comments TEXT, customernumber INT NOT NULL REFERENCES customers, last_update TIMESTAMP);
CREATE TABLE orderdetails (
  ordernumber INT NOT NULL REFERENCES orders, productcode VARCHAR(15) NOT NULL REFERENCES products, quantityordered INT NOT NULL,
  priceeach NUMERIC(10,2) NOT NULL, orderlinenumber INT NOT NULL, last_update TIMESTAMP, PRIMARY KEY (ordernumber, productcode));

INSERT INTO productlines VALUES ('Classic Cars',NULL),('Motorcycles',NULL),('Planes',NULL),('Ships',NULL),('Trains',NULL),('Trucks and Buses',NULL),('Vintage Cars',NULL);

INSERT INTO products VALUES
 ('S10_1678','1969 Harley Davidson Ultimate Chopper','Motorcycles','1:10','Min Lin Diecast','-',7933,48.81,95.70,NULL),
 ('S10_1949','1952 Alpine Renault 1300','Classic Cars','1:10','Classic Metal Creations','-',7305,98.58,214.30,NULL),
 ('S10_4698','2003 Harley-Davidson Eagle Drag Bike','Motorcycles','1:10','Red Start Diecast','-',5582,91.02,193.66,NULL),
 ('S12_1099','1968 Ford Mustang','Classic Cars','1:12','Autoart Studio Design','-',68,95.34,194.57,NULL),
 ('S12_1666','1958 Setra Bus','Trucks and Buses','1:12','Welly Diecast Productions','-',1579,77.90,136.67,NULL),
 ('S18_1097','1940 Ford Pickup Truck','Trucks and Buses','1:18','Studio M Art Models','-',2613,58.33,116.67,NULL),
 ('S18_2581','P-51-D Mustang','Planes','1:72','Gearbox Collectibles','-',992,49.00,84.48,NULL),
 ('S18_3029','1999 Yamaha Speed Boat','Ships','1:18','Min Lin Diecast','-',4259,51.61,86.02,NULL),
 ('S18_3259','Collectable Wooden Train','Trains','1:18','Carousel DieCast Legends','-',6450,67.56,100.84,NULL),
 ('S18_3140','1903 Ford Model A','Vintage Cars','1:18','Unimax Art Galleries','-',3913,68.30,136.59,NULL);

INSERT INTO offices VALUES
 ('1','San Francisco','+1 650 219 4782','100 Market Street','Suite 300','CA','USA','94080','NA'),
 ('4','Paris','+33 14 723 4404','43 Rue Jouffroy D''abbans',NULL,NULL,'France','75017','EMEA'),
 ('5','Tokyo','+81 33 224 5000','4-1 Kioicho',NULL,'Chiyoda-Ku','Japan','102-8578','Japan');
INSERT INTO employees VALUES
 (1002,'Murphy','Diane','x5800','dmurphy@classicmodelcars.com','1',NULL,'President'),
 (1337,'Bondur','Loui','x6493','lbondur@classicmodelcars.com','4',1002,'Sales Rep'),
 (1621,'Nishi','Mami','x101','mnishi@classicmodelcars.com','5',1002,'Sales Rep');

-- clients : pays écrits de façons différentes / avec espaces (cas réels de classicmodels)
INSERT INTO customers VALUES
 (103,'Atelier graphique','Schmitt','Carine','40.32.2555','54, rue Royale',NULL,'Nantes',NULL,'44000','France',1337,21000,NULL),
 (112,'Signal Gift Stores','King','Jean','7025551838','8489 Strong St.',NULL,'Las Vegas','NV','83030','USA',1002,71800,NULL),
 (114,'Australian Collectors, Co.','Ferguson','Peter','03 9520 4555','636 St Kilda Road','Level 3','Melbourne','Victoria','3004','Australia',1621,117300,NULL),
 (121,'Baane Mini Imports','Bergulfsen','Jonas','07-98 9555','Erling Skakkes gate 78',NULL,'Stavern',NULL,'4110','Norway  ',1337,81700,NULL),
 (124,'Mini Gifts Distributors Ltd.','Nelson','Susan','4155551450','5677 Strong St.',NULL,'San Rafael','CA','97562','USA',1002,210500,NULL),
 (141,'Euro+ Shopping Channel','Freyre','Diego','(91) 555 94 44','C/ Moralzarzal, 86',NULL,'Madrid','','28034','Spain',1337,227600,NULL),
 (148,'Dragon Souveniers, Ltd.','Natividad','Eric','+65 221 7555','Bronz Sok.','Bronz Apt. 3/6 Tesvikiye','Singapore',NULL,'079903','Singapore',1621,103800,NULL),
 (151,'Muscle Machine Inc','Young','Jeff','2125557413','4092 Furth Circle','Suite 400','NYC','NY','10022','USA',1002,138500,NULL),
 (166,'Handji Gifts& Co','Victorino','Wendy','+65 224 1555','106 Linden Road Sandown','2nd Floor','Singapore',NULL,'069045','Singapore',1621,97900,NULL),
 (171,'Daedalus Designs Imports','Rancé','Martine','20.16.1555','184, chaussée de Tournai',NULL,'Lille',NULL,'59000','France',1337,82900,NULL),
 (187,'AV Stores, Co.','Ashworth','Rachel','(171) 555-1555','Fauntleroy Circus',NULL,'Manchester',NULL,'EC2 5NT','UK',1337,136800,NULL),
 (250,'Lyon Souveniers','Da Silva','Daniel','+33 1 46 62 7555','27 rue du Colonel Pierre Avia',NULL,'Paris',NULL,'75508','France',1337,68100,NULL),
 (398,'Tokyo Collectables, Ltd','Shimamura','Akiko','+81 3 3584 0555','2-2-8 Roppongi',NULL,'Minato-ku','Tokyo','106-0032','Japan',1621,94400,NULL),
 (459,'Warburg Exchange','Ottlieb','Sven','0241-039123','Walserweg 21',NULL,'Aachen',NULL,'52066','Germany',1337,0,NULL);

-- 120 commandes générées entre 2003 et 2005 (déterministe)
SELECT setseed(0.42);
INSERT INTO orders
SELECT 10100 + g,
       DATE '2003-01-06' + (g * 7),
       DATE '2003-01-06' + (g * 7) + 10,
       DATE '2003-01-06' + (g * 7) + 3,
       CASE WHEN g % 23 = 0 THEN 'Cancelled' WHEN g % 17 = 0 THEN 'On Hold' WHEN g > 115 THEN 'In Process' ELSE 'Shipped' END,
       NULL,
       (ARRAY[103,112,114,121,124,141,148,151,166,171,187,250,398,459])[1 + (g % 14)],
       NULL
FROM generate_series(0, 119) AS g;

INSERT INTO orderdetails
SELECT o.ordernumber, p.productcode,
       20 + ((o.ordernumber * 7 + p.rn * 13) % 31),
       ROUND(p.msrp * (0.85 + ((o.ordernumber + p.rn) % 10) / 100.0), 2),
       p.rn, NULL
FROM orders o
JOIN (SELECT productcode, msrp, ROW_NUMBER() OVER (ORDER BY productcode) AS rn FROM products) p
  ON (o.ordernumber + p.rn) % 4 = 0;
