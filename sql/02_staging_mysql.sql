-- =====================================================================
--  PROJET BI - 02 : BD STAGING (MySQL du groupe : 172.20.0.6X:3306)
--  Zone de transit (slide 43) : NiFi y copie les données brutes des 2 OLTP,
--  la transformation se fait ici en SQL (procédure sp_transform, script 03),
--  puis NiFi recopie les tables dw_* vers la BD OLAP PostgreSQL.
--
--  Préfixes :  stg_cm_*  = copie de classicmodels (PostgreSQL)
--              stg_ds_*  = copie de dellstore     (SQL Server)
--              ref_*     = tables de référence (mapping, paramètres)
--              dw_*      = dimensions/faits transformés, prêts à charger
--              etl_*     = pilotage de l'ETL (watermark, journal)
--
--  Chaque table a une colonne etl_maj : MySQL la met à jour TOUT SEUL,
--  uniquement si une valeur de la ligne change réellement
--  (ON UPDATE CURRENT_TIMESTAMP). C'est ce qui permet le CDC (bonus).
--
--  À exécuter UNE fois (phpMyAdmin, onglet SQL) dans la base du groupe.
-- =====================================================================

-- Si vous avez le droit de créer une base, sinon sélectionnez la vôtre :
-- CREATE DATABASE IF NOT EXISTS staging_bi CHARACTER SET utf8mb4;
-- USE staging_bi;

SET NAMES utf8mb4;   -- sinon les accents ('Amérique', 'Modèles') sont abîmés

DROP VIEW  IF EXISTS v_clients;
DROP TABLE IF EXISTS dw_fact_ventes, dw_dim_produit, dw_dim_geographie;
DROP TABLE IF EXISTS stg_cm_products, stg_cm_customers, stg_cm_orders, stg_cm_orderdetails;
DROP TABLE IF EXISTS stg_ds_categories, stg_ds_products, stg_ds_customers, stg_ds_orders, stg_ds_orderlines;
DROP TABLE IF EXISTS ref_pays, ref_taux_cout_ds, etl_parametre, etl_controle, etl_journal;

-- =====================================================================
-- 1) TABLES DE STAGING "BRUTES" (remplies par NiFi en UPSERT)
--    On ne copie QUE les colonnes utiles (slide 44 : ne pas charger les
--    données non désirées) et AUCUNE donnée personnelle (slide 29 :
--    anonymisation) : pas de noms, téléphones, cartes de crédit, mots de passe.
-- =====================================================================

-- ---------- classicmodels (PostgreSQL) ----------
CREATE TABLE stg_cm_products (
    productcode     VARCHAR(15)    NOT NULL PRIMARY KEY,
    productname     VARCHAR(70)    NOT NULL,
    productline     VARCHAR(50)    NOT NULL,
    productvendor   VARCHAR(50),
    buyprice        DECIMAL(10,2)  NOT NULL,
    msrp            DECIMAL(10,2),
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_cm_customers (
    customernumber  INT            NOT NULL PRIMARY KEY,
    city            VARCHAR(50),
    state           VARCHAR(50),
    country         VARCHAR(50),
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_cm_orders (
    ordernumber     INT            NOT NULL PRIMARY KEY,
    orderdate       DATE           NOT NULL,
    status          VARCHAR(15),
    customernumber  INT            NOT NULL,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_cm_orderdetails (
    ordernumber     INT            NOT NULL,
    productcode     VARCHAR(15)    NOT NULL,
    quantityordered INT            NOT NULL,
    priceeach       DECIMAL(10,2)  NOT NULL,
    orderlinenumber INT,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (ordernumber, productcode)
);

-- ---------- dellstore (SQL Server) ----------
CREATE TABLE stg_ds_categories (
    category        INT            NOT NULL PRIMARY KEY,
    categoryname    VARCHAR(50)    NOT NULL,
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_ds_products (
    prod_id         INT            NOT NULL PRIMARY KEY,
    category        INT            NOT NULL,
    title           VARCHAR(100)   NOT NULL,
    actor           VARCHAR(100),
    price           DECIMAL(12,2)  NOT NULL,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_ds_customers (
    customerid      INT            NOT NULL PRIMARY KEY,
    city            VARCHAR(50),
    state           VARCHAR(50),
    country         VARCHAR(50),
    region          SMALLINT,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_ds_orders (
    orderid         INT            NOT NULL PRIMARY KEY,
    orderdate       DATE           NOT NULL,
    customerid      INT,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);

CREATE TABLE stg_ds_orderlines (
    orderid         INT            NOT NULL,
    orderlineid     INT            NOT NULL,
    prod_id         INT            NOT NULL,
    quantity        INT            NOT NULL,
    orderdate       DATE,
    last_update     DATETIME(3),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (orderid, orderlineid)
);

-- =====================================================================
-- 2) TABLES DE RÉFÉRENCE (uniformisation des données, slide 46-48)
-- =====================================================================

-- Les 2 sources n'écrivent pas les pays pareil ('USA' vs 'US', 'Norway  ' avec
-- des espaces...). On ramène tout à un nom unique + une zone géographique commune.
CREATE TABLE ref_pays (
    pays_source     VARCHAR(50)    NOT NULL PRIMARY KEY,   -- valeur source en MAJUSCULES, sans espaces autour
    pays            VARCHAR(50)    NOT NULL,               -- nom normalisé (anglais : reconnu par la carte Power BI)
    code_iso2       CHAR(2)        NOT NULL,
    zone            VARCHAR(30)    NOT NULL
);

INSERT INTO ref_pays (pays_source, pays, code_iso2, zone) VALUES
 ('USA','United States','US','Amérique du Nord'), ('US','United States','US','Amérique du Nord'),
 ('UNITED STATES','United States','US','Amérique du Nord'), ('CANADA','Canada','CA','Amérique du Nord'),
 ('MEXICO','Mexico','MX','Amérique latine'), ('BRAZIL','Brazil','BR','Amérique latine'),
 ('CHILE','Chile','CL','Amérique latine'), ('ARGENTINA','Argentina','AR','Amérique latine'),
 ('FRANCE','France','FR','Europe'), ('BELGIUM','Belgium','BE','Europe'), ('GERMANY','Germany','DE','Europe'),
 ('UK','United Kingdom','GB','Europe'), ('UNITED KINGDOM','United Kingdom','GB','Europe'),
 ('IRELAND','Ireland','IE','Europe'), ('SPAIN','Spain','ES','Europe'), ('PORTUGAL','Portugal','PT','Europe'),
 ('ITALY','Italy','IT','Europe'), ('SWITZERLAND','Switzerland','CH','Europe'), ('AUSTRIA','Austria','AT','Europe'),
 ('NETHERLANDS','Netherlands','NL','Europe'), ('LUXEMBOURG','Luxembourg','LU','Europe'),
 ('DENMARK','Denmark','DK','Europe'), ('NORWAY','Norway','NO','Europe'), ('SWEDEN','Sweden','SE','Europe'),
 ('FINLAND','Finland','FI','Europe'), ('POLAND','Poland','PL','Europe'), ('RUSSIA','Russia','RU','Europe'),
 ('JAPAN','Japan','JP','Asie-Pacifique'), ('CHINA','China','CN','Asie-Pacifique'),
 ('HONG KONG','Hong Kong','HK','Asie-Pacifique'), ('SINGAPORE','Singapore','SG','Asie-Pacifique'),
 ('PHILIPPINES','Philippines','PH','Asie-Pacifique'), ('INDIA','India','IN','Asie-Pacifique'),
 ('AUSTRALIA','Australia','AU','Asie-Pacifique'), ('NEW ZEALAND','New Zealand','NZ','Asie-Pacifique'),
 ('SOUTH AFRICA','South Africa','ZA','Afrique'), ('ISRAEL','Israel','IL','Moyen-Orient');

-- Pays supplémentaires présents dans les vraies données (classicmodels modifiée par le prof)
-- + pays courants, pour que presque aucun client ne tombe dans la zone 'Autre'.
INSERT IGNORE INTO ref_pays (pays_source, pays, code_iso2, zone) VALUES
 ('AMERICAN SAMOA','American Samoa','AS','Asie-Pacifique'), ('ANTIGUA AND BARBUDA','Antigua and Barbuda','AG','Amérique latine'),
 ('AZERBAIJAN','Azerbaijan','AZ','Moyen-Orient'), ('BANGLADESH','Bangladesh','BD','Asie-Pacifique'),
 ('BARBADOS','Barbados','BB','Amérique latine'), ('BELARUS','Belarus','BY','Europe'), ('BERMUDA','Bermuda','BM','Amérique du Nord'),
 ('BOSNIA AND HERZEGOVINA','Bosnia and Herzegovina','BA','Europe'), ('BULGARIA','Bulgaria','BG','Europe'),
 ('BURUNDI','Burundi','BI','Afrique'), ('CHAD','Chad','TD','Afrique'), ('COLOMBIA','Colombia','CO','Amérique latine'),
 ('CONGO','Congo','CG','Afrique'), ('CROATIA','Croatia','HR','Europe'), ('CYPRUS','Cyprus','CY','Europe'),
 ('CZECH REPUBLIC','Czech Republic','CZ','Europe'), ('CZECHIA','Czech Republic','CZ','Europe'), ('DJIBOUTI','Djibouti','DJ','Afrique'),
 ('DOMINICAN REPUBLIC','Dominican Republic','DO','Amérique latine'), ('ECUADOR','Ecuador','EC','Amérique latine'),
 ('EGYPT','Egypt','EG','Afrique'), ('ERITREA','Eritrea','ER','Afrique'), ('FIJI ISLANDS','Fiji','FJ','Asie-Pacifique'), ('FIJI','Fiji','FJ','Asie-Pacifique'),
 ('GRENADA','Grenada','GD','Amérique latine'), ('GUATEMALA','Guatemala','GT','Amérique latine'),
 ('GUERNSEY AND ALDERNEY','Guernsey','GG','Europe'), ('GUINEA-BISSAU','Guinea-Bissau','GW','Afrique'),
 ('HONDURAS','Honduras','HN','Amérique latine'), ('JAMAICA','Jamaica','JM','Amérique latine'), ('LEBANON','Lebanon','LB','Moyen-Orient'),
 ('MACAU S.A.R.','Macao','MO','Asie-Pacifique'), ('MACAU','Macao','MO','Asie-Pacifique'), ('MAYOTTE','Mayotte','YT','Afrique'),
 ('MOLDOVA','Moldova','MD','Europe'), ('MONTENEGRO','Montenegro','ME','Europe'), ('MYANMAR','Myanmar','MM','Asie-Pacifique'),
 ('NAURU','Nauru','NR','Asie-Pacifique'), ('NEW CALEDONIA','New Caledonia','NC','Asie-Pacifique'),
 ('NORTH MACEDONIA','North Macedonia','MK','Europe'), ('PANAMA','Panama','PA','Amérique latine'),
 ('PITCAIRN ISLAND','Pitcairn Islands','PN','Asie-Pacifique'), ('RWANDA','Rwanda','RW','Afrique'),
 ('SAO TOME AND PRINCIPE','Sao Tome and Principe','ST','Afrique'), ('SERBIA','Serbia','RS','Europe'),
 ('SEYCHELLES','Seychelles','SC','Afrique'), ('SIERRA LEONE','Sierra Leone','SL','Afrique'), ('SLOVAKIA','Slovakia','SK','Europe'),
 ('SRI LANKA','Sri Lanka','LK','Asie-Pacifique'), ('TAIWAN','Taiwan','TW','Asie-Pacifique'), ('TANZANIA','Tanzania','TZ','Afrique'),
 ('THE BAHAMAS','Bahamas','BS','Amérique latine'), ('BAHAMAS','Bahamas','BS','Amérique latine'), ('UKRAINE','Ukraine','UA','Europe'),
 ('URUGUAY','Uruguay','UY','Amérique latine'), ('VENEZUELA','Venezuela','VE','Amérique latine'), ('ZIMBABWE','Zimbabwe','ZW','Afrique'),
 ('GREECE','Greece','GR','Europe'), ('TURKEY','Turkey','TR','Moyen-Orient'), ('ROMANIA','Romania','RO','Europe'), ('HUNGARY','Hungary','HU','Europe'),
 ('ICELAND','Iceland','IS','Europe'), ('ESTONIA','Estonia','EE','Europe'), ('LATVIA','Latvia','LV','Europe'), ('LITHUANIA','Lithuania','LT','Europe'),
 ('SLOVENIA','Slovenia','SI','Europe'), ('ALBANIA','Albania','AL','Europe'), ('MALTA','Malta','MT','Europe'), ('GEORGIA','Georgia','GE','Moyen-Orient'),
 ('ARMENIA','Armenia','AM','Moyen-Orient'), ('SAUDI ARABIA','Saudi Arabia','SA','Moyen-Orient'), ('UNITED ARAB EMIRATES','United Arab Emirates','AE','Moyen-Orient'),
 ('QATAR','Qatar','QA','Moyen-Orient'), ('KUWAIT','Kuwait','KW','Moyen-Orient'), ('JORDAN','Jordan','JO','Moyen-Orient'), ('IRAN','Iran','IR','Moyen-Orient'),
 ('IRAQ','Iraq','IQ','Moyen-Orient'), ('SOUTH KOREA','South Korea','KR','Asie-Pacifique'), ('KOREA','South Korea','KR','Asie-Pacifique'),
 ('THAILAND','Thailand','TH','Asie-Pacifique'), ('VIETNAM','Vietnam','VN','Asie-Pacifique'), ('INDONESIA','Indonesia','ID','Asie-Pacifique'),
 ('MALAYSIA','Malaysia','MY','Asie-Pacifique'), ('PAKISTAN','Pakistan','PK','Asie-Pacifique'), ('NEPAL','Nepal','NP','Asie-Pacifique'),
 ('CAMBODIA','Cambodia','KH','Asie-Pacifique'), ('MONGOLIA','Mongolia','MN','Asie-Pacifique'), ('KAZAKHSTAN','Kazakhstan','KZ','Asie-Pacifique'),
 ('PERU','Peru','PE','Amérique latine'), ('BOLIVIA','Bolivia','BO','Amérique latine'), ('PARAGUAY','Paraguay','PY','Amérique latine'),
 ('CUBA','Cuba','CU','Amérique latine'), ('COSTA RICA','Costa Rica','CR','Amérique latine'), ('EL SALVADOR','El Salvador','SV','Amérique latine'),
 ('NICARAGUA','Nicaragua','NI','Amérique latine'), ('HAITI','Haiti','HT','Amérique latine'), ('PUERTO RICO','Puerto Rico','PR','Amérique latine'),
 ('TRINIDAD AND TOBAGO','Trinidad and Tobago','TT','Amérique latine'), ('MOROCCO','Morocco','MA','Afrique'), ('ALGERIA','Algeria','DZ','Afrique'),
 ('TUNISIA','Tunisia','TN','Afrique'), ('NIGERIA','Nigeria','NG','Afrique'), ('KENYA','Kenya','KE','Afrique'), ('SENEGAL','Senegal','SN','Afrique'),
 ('GHANA','Ghana','GH','Afrique'), ('CAMEROON','Cameroon','CM','Afrique'), ('ETHIOPIA','Ethiopia','ET','Afrique'), ('ANGOLA','Angola','AO','Afrique'),
 ('MOZAMBIQUE','Mozambique','MZ','Afrique'), ('MADAGASCAR','Madagascar','MG','Afrique');

-- Liste mondiale complète (250 pays, base libre dr5hn/countries-states-cities-database) :
-- dellstore contient des clients dans ~tous les pays du monde. Zone déduite de la
-- région / sous-région du pays. INSERT IGNORE : les lignes ci-dessus restent prioritaires.
INSERT IGNORE INTO ref_pays (pays_source, pays, code_iso2, zone) VALUES
 ('AFGHANISTAN','Afghanistan','AF','Asie-Pacifique'), ('ALAND ISLANDS','Aland Islands','AX','Europe'), ('ALBANIA','Albania','AL','Europe'),
 ('ALGERIA','Algeria','DZ','Afrique'), ('AMERICAN SAMOA','American Samoa','AS','Asie-Pacifique'), ('ANDORRA','Andorra','AD','Europe'),
 ('ANGOLA','Angola','AO','Afrique'), ('ANGUILLA','Anguilla','AI','Amérique latine'), ('ANTARCTICA','Antarctica','AQ','Autre'),
 ('ANTIGUA AND BARBUDA','Antigua and Barbuda','AG','Amérique latine'), ('ARGENTINA','Argentina','AR','Amérique latine'), ('ARMENIA','Armenia','AM','Moyen-Orient'),
 ('ARUBA','Aruba','AW','Amérique latine'), ('AUSTRALIA','Australia','AU','Asie-Pacifique'), ('AUSTRIA','Austria','AT','Europe'),
 ('AZERBAIJAN','Azerbaijan','AZ','Moyen-Orient'), ('BAHRAIN','Bahrain','BH','Moyen-Orient'), ('BANGLADESH','Bangladesh','BD','Asie-Pacifique'),
 ('BARBADOS','Barbados','BB','Amérique latine'), ('BELARUS','Belarus','BY','Europe'), ('BELGIUM','Belgium','BE','Europe'),
 ('BELIZE','Belize','BZ','Amérique latine'), ('BENIN','Benin','BJ','Afrique'), ('BERMUDA','Bermuda','BM','Amérique du Nord'),
 ('BHUTAN','Bhutan','BT','Asie-Pacifique'), ('BOLIVIA','Bolivia','BO','Amérique latine'), ('BONAIRE, SINT EUSTATIUS AND SABA','Bonaire, Sint Eustatius and Saba','BQ','Amérique latine'),
 ('BOSNIA AND HERZEGOVINA','Bosnia and Herzegovina','BA','Europe'), ('BOTSWANA','Botswana','BW','Afrique'), ('BOUVET ISLAND','Bouvet Island','BV','Autre'),
 ('BRAZIL','Brazil','BR','Amérique latine'), ('BRITISH INDIAN OCEAN TERRITORY','British Indian Ocean Territory','IO','Afrique'), ('BRUNEI','Brunei','BN','Asie-Pacifique'),
 ('BULGARIA','Bulgaria','BG','Europe'), ('BURKINA FASO','Burkina Faso','BF','Afrique'), ('BURUNDI','Burundi','BI','Afrique'),
 ('CAMBODIA','Cambodia','KH','Asie-Pacifique'), ('CAMEROON','Cameroon','CM','Afrique'), ('CANADA','Canada','CA','Amérique du Nord'),
 ('CAPE VERDE','Cape Verde','CV','Afrique'), ('CAYMAN ISLANDS','Cayman Islands','KY','Amérique latine'), ('CENTRAL AFRICAN REPUBLIC','Central African Republic','CF','Afrique'),
 ('CHAD','Chad','TD','Afrique'), ('CHILE','Chile','CL','Amérique latine'), ('CHINA','China','CN','Asie-Pacifique'),
 ('CHRISTMAS ISLAND','Christmas Island','CX','Asie-Pacifique'), ('COCOS (KEELING) ISLANDS','Cocos (Keeling) Islands','CC','Asie-Pacifique'), ('COLOMBIA','Colombia','CO','Amérique latine'),
 ('COMOROS','Comoros','KM','Afrique'), ('CONGO','Congo','CG','Afrique'), ('COOK ISLANDS','Cook Islands','CK','Asie-Pacifique'),
 ('COSTA RICA','Costa Rica','CR','Amérique latine'), ('CROATIA','Croatia','HR','Europe'), ('CUBA','Cuba','CU','Amérique latine'),
 ('CURAÇAO','Curaçao','CW','Amérique latine'), ('CYPRUS','Cyprus','CY','Europe'), ('CZECH REPUBLIC','Czech Republic','CZ','Europe'),
 ('DEMOCRATIC REPUBLIC OF THE CONGO','Democratic Republic of the Congo','CD','Afrique'), ('DENMARK','Denmark','DK','Europe'), ('DJIBOUTI','Djibouti','DJ','Afrique'),
 ('DOMINICA','Dominica','DM','Amérique latine'), ('DOMINICAN REPUBLIC','Dominican Republic','DO','Amérique latine'), ('ECUADOR','Ecuador','EC','Amérique latine'),
 ('EGYPT','Egypt','EG','Afrique'), ('EL SALVADOR','El Salvador','SV','Amérique latine'), ('EQUATORIAL GUINEA','Equatorial Guinea','GQ','Afrique'),
 ('ERITREA','Eritrea','ER','Afrique'), ('ESTONIA','Estonia','EE','Europe'), ('ESWATINI','Eswatini','SZ','Afrique'),
 ('ETHIOPIA','Ethiopia','ET','Afrique'), ('FALKLAND ISLANDS','Falkland Islands','FK','Amérique latine'), ('FAROE ISLANDS','Faroe Islands','FO','Europe'),
 ('FIJI ISLANDS','Fiji Islands','FJ','Asie-Pacifique'), ('FINLAND','Finland','FI','Europe'), ('FRANCE','France','FR','Europe'),
 ('FRENCH GUIANA','French Guiana','GF','Amérique latine'), ('FRENCH POLYNESIA','French Polynesia','PF','Asie-Pacifique'), ('FRENCH SOUTHERN TERRITORIES','French Southern Territories','TF','Afrique'),
 ('GABON','Gabon','GA','Afrique'), ('GEORGIA','Georgia','GE','Moyen-Orient'), ('GERMANY','Germany','DE','Europe'),
 ('GHANA','Ghana','GH','Afrique'), ('GIBRALTAR','Gibraltar','GI','Europe'), ('GREECE','Greece','GR','Europe'),
 ('GREENLAND','Greenland','GL','Amérique du Nord'), ('GRENADA','Grenada','GD','Amérique latine'), ('GUADELOUPE','Guadeloupe','GP','Amérique latine'),
 ('GUAM','Guam','GU','Asie-Pacifique'), ('GUATEMALA','Guatemala','GT','Amérique latine'), ('GUERNSEY','Guernsey','GG','Europe'),
 ('GUINEA','Guinea','GN','Afrique'), ('GUINEA-BISSAU','Guinea-Bissau','GW','Afrique'), ('GUYANA','Guyana','GY','Amérique latine'),
 ('HAITI','Haiti','HT','Amérique latine'), ('HEARD ISLAND AND MCDONALD ISLANDS','Heard Island and McDonald Islands','HM','Autre'), ('HONDURAS','Honduras','HN','Amérique latine'),
 ('HONG KONG S.A.R.','Hong Kong S.A.R.','HK','Asie-Pacifique'), ('HUNGARY','Hungary','HU','Europe'), ('ICELAND','Iceland','IS','Europe'),
 ('INDIA','India','IN','Asie-Pacifique'), ('INDONESIA','Indonesia','ID','Asie-Pacifique'), ('IRAN','Iran','IR','Asie-Pacifique'),
 ('IRAQ','Iraq','IQ','Moyen-Orient'), ('IRELAND','Ireland','IE','Europe'), ('ISRAEL','Israel','IL','Moyen-Orient'),
 ('ITALY','Italy','IT','Europe'), ('IVORY COAST','Ivory Coast','CI','Afrique'), ('JAMAICA','Jamaica','JM','Amérique latine'),
 ('JAPAN','Japan','JP','Asie-Pacifique'), ('JERSEY','Jersey','JE','Europe'), ('JORDAN','Jordan','JO','Moyen-Orient'),
 ('KAZAKHSTAN','Kazakhstan','KZ','Asie-Pacifique'), ('KENYA','Kenya','KE','Afrique'), ('KIRIBATI','Kiribati','KI','Asie-Pacifique'),
 ('KOSOVO','Kosovo','XK','Europe'), ('KUWAIT','Kuwait','KW','Moyen-Orient'), ('KYRGYZSTAN','Kyrgyzstan','KG','Asie-Pacifique'),
 ('LAOS','Laos','LA','Asie-Pacifique'), ('LATVIA','Latvia','LV','Europe'), ('LEBANON','Lebanon','LB','Moyen-Orient'),
 ('LESOTHO','Lesotho','LS','Afrique'), ('LIBERIA','Liberia','LR','Afrique'), ('LIBYA','Libya','LY','Afrique'),
 ('LIECHTENSTEIN','Liechtenstein','LI','Europe'), ('LITHUANIA','Lithuania','LT','Europe'), ('LUXEMBOURG','Luxembourg','LU','Europe'),
 ('MACAU S.A.R.','Macau S.A.R.','MO','Asie-Pacifique'), ('MADAGASCAR','Madagascar','MG','Afrique'), ('MALAWI','Malawi','MW','Afrique'),
 ('MALAYSIA','Malaysia','MY','Asie-Pacifique'), ('MALDIVES','Maldives','MV','Asie-Pacifique'), ('MALI','Mali','ML','Afrique'),
 ('MALTA','Malta','MT','Europe'), ('MAN (ISLE OF)','Man (Isle of)','IM','Europe'), ('MARSHALL ISLANDS','Marshall Islands','MH','Asie-Pacifique'),
 ('MARTINIQUE','Martinique','MQ','Amérique latine'), ('MAURITANIA','Mauritania','MR','Afrique'), ('MAURITIUS','Mauritius','MU','Afrique'),
 ('MAYOTTE','Mayotte','YT','Afrique'), ('MEXICO','Mexico','MX','Amérique du Nord'), ('MICRONESIA','Micronesia','FM','Asie-Pacifique'),
 ('MOLDOVA','Moldova','MD','Europe'), ('MONACO','Monaco','MC','Europe'), ('MONGOLIA','Mongolia','MN','Asie-Pacifique'),
 ('MONTENEGRO','Montenegro','ME','Europe'), ('MONTSERRAT','Montserrat','MS','Amérique latine'), ('MOROCCO','Morocco','MA','Afrique'),
 ('MOZAMBIQUE','Mozambique','MZ','Afrique'), ('MYANMAR','Myanmar','MM','Asie-Pacifique'), ('NAMIBIA','Namibia','NA','Afrique'),
 ('NAURU','Nauru','NR','Asie-Pacifique'), ('NEPAL','Nepal','NP','Asie-Pacifique'), ('NETHERLANDS','Netherlands','NL','Europe'),
 ('NEW CALEDONIA','New Caledonia','NC','Asie-Pacifique'), ('NEW ZEALAND','New Zealand','NZ','Asie-Pacifique'), ('NICARAGUA','Nicaragua','NI','Amérique latine'),
 ('NIGER','Niger','NE','Afrique'), ('NIGERIA','Nigeria','NG','Afrique'), ('NIUE','Niue','NU','Asie-Pacifique'),
 ('NORFOLK ISLAND','Norfolk Island','NF','Asie-Pacifique'), ('NORTH KOREA','North Korea','KP','Asie-Pacifique'), ('NORTH MACEDONIA','North Macedonia','MK','Europe'),
 ('NORTHERN MARIANA ISLANDS','Northern Mariana Islands','MP','Asie-Pacifique'), ('NORWAY','Norway','NO','Europe'), ('OMAN','Oman','OM','Moyen-Orient'),
 ('PAKISTAN','Pakistan','PK','Asie-Pacifique'), ('PALAU','Palau','PW','Asie-Pacifique'), ('PALESTINE','Palestine','PS','Moyen-Orient'),
 ('PANAMA','Panama','PA','Amérique latine'), ('PAPUA NEW GUINEA','Papua New Guinea','PG','Asie-Pacifique'), ('PARAGUAY','Paraguay','PY','Amérique latine'),
 ('PERU','Peru','PE','Amérique latine'), ('PHILIPPINES','Philippines','PH','Asie-Pacifique'), ('PITCAIRN ISLAND','Pitcairn Island','PN','Asie-Pacifique'),
 ('POLAND','Poland','PL','Europe'), ('PORTUGAL','Portugal','PT','Europe'), ('PUERTO RICO','Puerto Rico','PR','Amérique latine'),
 ('QATAR','Qatar','QA','Moyen-Orient'), ('REUNION','Reunion','RE','Afrique'), ('ROMANIA','Romania','RO','Europe'),
 ('RUSSIA','Russia','RU','Europe'), ('RWANDA','Rwanda','RW','Afrique'), ('SAINT HELENA','Saint Helena','SH','Afrique'),
 ('SAINT KITTS AND NEVIS','Saint Kitts and Nevis','KN','Amérique latine'), ('SAINT LUCIA','Saint Lucia','LC','Amérique latine'), ('SAINT PIERRE AND MIQUELON','Saint Pierre and Miquelon','PM','Amérique du Nord'),
 ('SAINT VINCENT AND THE GRENADINES','Saint Vincent and the Grenadines','VC','Amérique latine'), ('SAINT-BARTHELEMY','Saint-Barthelemy','BL','Amérique latine'), ('SAINT-MARTIN (FRENCH PART)','Saint-Martin (French part)','MF','Amérique latine'),
 ('SAMOA','Samoa','WS','Asie-Pacifique'), ('SAN MARINO','San Marino','SM','Europe'), ('SAO TOME AND PRINCIPE','Sao Tome and Principe','ST','Afrique'),
 ('SAUDI ARABIA','Saudi Arabia','SA','Moyen-Orient'), ('SENEGAL','Senegal','SN','Afrique'), ('SERBIA','Serbia','RS','Europe'),
 ('SEYCHELLES','Seychelles','SC','Afrique'), ('SIERRA LEONE','Sierra Leone','SL','Afrique'), ('SINGAPORE','Singapore','SG','Asie-Pacifique'),
 ('SINT MAARTEN (DUTCH PART)','Sint Maarten (Dutch part)','SX','Amérique latine'), ('SLOVAKIA','Slovakia','SK','Europe'), ('SLOVENIA','Slovenia','SI','Europe'),
 ('SOLOMON ISLANDS','Solomon Islands','SB','Asie-Pacifique'), ('SOMALIA','Somalia','SO','Afrique'), ('SOUTH AFRICA','South Africa','ZA','Afrique'),
 ('SOUTH GEORGIA','South Georgia','GS','Amérique latine'), ('SOUTH KOREA','South Korea','KR','Asie-Pacifique'), ('SOUTH SUDAN','South Sudan','SS','Afrique'),
 ('SPAIN','Spain','ES','Europe'), ('SRI LANKA','Sri Lanka','LK','Asie-Pacifique'), ('SUDAN','Sudan','SD','Afrique'),
 ('SURINAME','Suriname','SR','Amérique latine'), ('SVALBARD AND JAN MAYEN ISLANDS','Svalbard and Jan Mayen Islands','SJ','Europe'), ('SWEDEN','Sweden','SE','Europe'),
 ('SWITZERLAND','Switzerland','CH','Europe'), ('SYRIA','Syria','SY','Moyen-Orient'), ('TAIWAN','Taiwan','TW','Asie-Pacifique'),
 ('TAJIKISTAN','Tajikistan','TJ','Asie-Pacifique'), ('TANZANIA','Tanzania','TZ','Afrique'), ('THAILAND','Thailand','TH','Asie-Pacifique'),
 ('THE BAHAMAS','The Bahamas','BS','Amérique latine'), ('THE GAMBIA','The Gambia','GM','Afrique'), ('TIMOR-LESTE','Timor-Leste','TL','Asie-Pacifique'),
 ('TOGO','Togo','TG','Afrique'), ('TOKELAU','Tokelau','TK','Asie-Pacifique'), ('TONGA','Tonga','TO','Asie-Pacifique'),
 ('TRINIDAD AND TOBAGO','Trinidad and Tobago','TT','Amérique latine'), ('TUNISIA','Tunisia','TN','Afrique'), ('TURKEY','Turkey','TR','Moyen-Orient'),
 ('TURKMENISTAN','Turkmenistan','TM','Asie-Pacifique'), ('TURKS AND CAICOS ISLANDS','Turks and Caicos Islands','TC','Amérique latine'), ('TUVALU','Tuvalu','TV','Asie-Pacifique'),
 ('UGANDA','Uganda','UG','Afrique'), ('UKRAINE','Ukraine','UA','Europe'), ('UNITED ARAB EMIRATES','United Arab Emirates','AE','Moyen-Orient'),
 ('UNITED KINGDOM','United Kingdom','GB','Europe'), ('UNITED STATES','United States','US','Amérique du Nord'), ('UNITED STATES MINOR OUTLYING ISLANDS','United States Minor Outlying Islands','UM','Amérique du Nord'),
 ('URUGUAY','Uruguay','UY','Amérique latine'), ('UZBEKISTAN','Uzbekistan','UZ','Asie-Pacifique'), ('VANUATU','Vanuatu','VU','Asie-Pacifique'),
 ('VATICAN CITY STATE (HOLY SEE)','Vatican City State (Holy See)','VA','Europe'), ('VENEZUELA','Venezuela','VE','Amérique latine'), ('VIETNAM','Vietnam','VN','Asie-Pacifique'),
 ('VIRGIN ISLANDS (BRITISH)','Virgin Islands (British)','VG','Amérique latine'), ('VIRGIN ISLANDS (US)','Virgin Islands (US)','VI','Amérique latine'), ('WALLIS AND FUTUNA ISLANDS','Wallis and Futuna Islands','WF','Asie-Pacifique'),
 ('WESTERN SAHARA','Western Sahara','EH','Afrique'), ('YEMEN','Yemen','YE','Moyen-Orient'), ('ZAMBIA','Zambia','ZM','Afrique'),
 ('ZIMBABWE','Zimbabwe','ZW','Afrique'), ('COTE D''IVOIRE (IVORY COAST)','Ivory Coast','CI','Afrique'), ('PALESTINIAN TERRITORY OCCUPIED','Palestine','PS','Moyen-Orient');

-- dellstore n'a PAS de prix d'achat -> la marge brute doit être estimée.
-- Hypothèse (à valider avec le prof) : coût d'achat = taux x prix de vente.
CREATE TABLE etl_parametre (
    cle     VARCHAR(50)    NOT NULL PRIMARY KEY,
    valeur  DECIMAL(10,4)  NOT NULL,
    commentaire VARCHAR(200)
);
INSERT INTO etl_parametre VALUES
 ('taux_cout_dellstore', 0.6500, 'Coût d''achat estimé = 65 % du prix de vente (marge brute 35 %)');

-- Optionnel : un taux différent par catégorie dellstore (sinon le taux par défaut ci-dessus)
CREATE TABLE ref_taux_cout_ds (
    category    INT            NOT NULL PRIMARY KEY,
    taux_cout   DECIMAL(5,4)   NOT NULL
);

-- =====================================================================
-- 3) TABLES TRANSFORMÉES (dw_*) = contenu final de la BD OLAP
--    Les clés techniques (surrogate keys) sont générées ICI (AUTO_INCREMENT)
--    et ne changent jamais pour une même clé métier (UNIQUE KEY).
-- =====================================================================
CREATE TABLE dw_dim_produit (
    produit_sk      INT            NOT NULL AUTO_INCREMENT PRIMARY KEY,
    univers         VARCHAR(30)    NOT NULL,
    categorie       VARCHAR(50)    NOT NULL,
    libelle         VARCHAR(100)   NOT NULL,
    code_produit    VARCHAR(20)    NOT NULL,
    source          VARCHAR(20)    NOT NULL,
    fournisseur     VARCHAR(60),
    prix_catalogue  DECIMAL(10,2),
    cout_unitaire   DECIMAL(10,2),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uk_produit (source, code_produit),
    KEY ix_maj (etl_maj)
);

CREATE TABLE dw_dim_geographie (
    geo_sk          INT            NOT NULL AUTO_INCREMENT PRIMARY KEY,
    zone            VARCHAR(30)    NOT NULL,
    pays            VARCHAR(50)    NOT NULL,
    etat_province   VARCHAR(50)    NOT NULL,
    ville           VARCHAR(50)    NOT NULL,
    code_pays       CHAR(2),
    etl_maj         DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uk_geo (pays, etat_province, ville),
    KEY ix_maj (etl_maj)
);

CREATE TABLE dw_fact_ventes (
    vente_sk          BIGINT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
    date_sk           INT            NOT NULL,
    produit_sk        INT            NOT NULL,
    geo_sk            INT            NOT NULL,
    quantite          INT            NOT NULL,
    prix_unitaire     DECIMAL(10,2)  NOT NULL,
    cout_unitaire     DECIMAL(10,2)  NOT NULL,
    chiffre_affaires  DECIMAL(12,2)  NOT NULL,
    cout_achat        DECIMAL(12,2)  NOT NULL,
    marge_brute       DECIMAL(12,2)  NOT NULL,
    source            VARCHAR(20)    NOT NULL,
    num_commande      INT            NOT NULL,
    ligne_source      VARCHAR(20)    NOT NULL,
    statut_commande   VARCHAR(20)    NOT NULL,
    etl_maj           DATETIME(3)    NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uk_vente (source, num_commande, ligne_source),
    KEY ix_maj (etl_maj)
);

-- =====================================================================
-- 4) PILOTAGE DE L'ETL
-- =====================================================================
-- Watermark : date du dernier passage de la transformation (CDC)
CREATE TABLE etl_controle (
    etape               VARCHAR(30)  NOT NULL PRIMARY KEY,
    derniere_execution  DATETIME(3)  NULL
);
INSERT INTO etl_controle VALUES ('transform', NULL);

-- Journal de chaque exécution (vérification post-import, slide 49)
CREATE TABLE etl_journal (
    id                  INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    debut               DATETIME(3)  NOT NULL,
    fin                 DATETIME(3),
    watermark_utilise   DATETIME(3),
    nb_produits         INT,
    nb_geo              INT,
    nb_ventes_cm        INT,
    nb_ventes_ds        INT,
    statut              VARCHAR(10)
);

-- =====================================================================
-- 5) VUE : clients des 2 sources, géographie uniformisée
-- =====================================================================
CREATE VIEW v_clients AS
SELECT  'classicmodels'                                  AS source,
        c.customernumber                                 AS client_id,
        COALESCE(rp.zone, 'Autre')                       AS zone,
        COALESCE(rp.pays, TRIM(c.country), 'Inconnu')    AS pays,
        rp.code_iso2                                     AS code_pays,
        COALESCE(NULLIF(TRIM(c.state), ''), 'N/A')       AS etat_province,
        COALESCE(NULLIF(TRIM(c.city),  ''), 'N/A')       AS ville
FROM stg_cm_customers c
LEFT JOIN ref_pays rp ON rp.pays_source = UPPER(TRIM(c.country))
UNION ALL
SELECT  'dellstore',
        c.customerid,
        COALESCE(rp.zone, 'Autre'),
        COALESCE(rp.pays, TRIM(c.country), 'Inconnu'),
        rp.code_iso2,
        COALESCE(NULLIF(TRIM(c.state), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(c.city),  ''), 'N/A')
FROM stg_ds_customers c
LEFT JOIN ref_pays rp ON rp.pays_source = UPPER(TRIM(c.country));
