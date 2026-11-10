-- =====================================================================
--  PROJET BI - 04 : CONTRÔLES APRÈS CHARGEMENT (slide 49 : "ne pas oublier
--  les procédures de vérification post-importation")
--  Les totaux doivent être IDENTIQUES entre les sources et la BD OLAP.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) Dans classicmodels (PostgreSQL OLTP 172.20.0.4)
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                              AS nb_lignes,
       SUM(od.quantityordered * od.priceeach)                AS ca,
       SUM(od.quantityordered * (od.priceeach - p.buyprice)) AS marge_brute
FROM orderdetails od
JOIN products p ON p.productcode = od.productcode;

-- ---------------------------------------------------------------------
-- B) Dans dellstore (SQL Server OLTP 172.20.0.3)
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS nb_lignes, SUM(ol.quantity * p.price) AS ca
FROM orderlines ol
JOIN products p ON p.prod_id = ol.prod_id;

-- ---------------------------------------------------------------------
-- C) Dans le staging MySQL
-- ---------------------------------------------------------------------
-- Journal des transformations (OK / ERREUR, nb de lignes traitées)
SELECT * FROM etl_journal ORDER BY id DESC LIMIT 10;

-- Pays non reconnus par ref_pays (=> à ajouter dans ref_pays, puis relancer)
SELECT DISTINCT source, pays FROM v_clients WHERE zone = 'Autre';

-- Lignes de commande qui n'ont PAS pu être transformées (produit ou client manquant)
SELECT 'classicmodels' AS source, COUNT(*) AS lignes_orphelines
FROM stg_cm_orderdetails od
WHERE NOT EXISTS (SELECT 1 FROM dw_fact_ventes f
                  WHERE f.source = 'classicmodels' AND f.num_commande = od.ordernumber AND f.ligne_source = od.productcode)
UNION ALL
SELECT 'dellstore', COUNT(*)
FROM stg_ds_orderlines ol
WHERE NOT EXISTS (SELECT 1 FROM dw_fact_ventes f
                  WHERE f.source = 'dellstore' AND f.num_commande = ol.orderid AND f.ligne_source = CAST(ol.orderlineid AS CHAR));

-- ---------------------------------------------------------------------
-- D) Dans la BD OLAP PostgreSQL (à comparer avec A et B)
-- ---------------------------------------------------------------------
SELECT source, COUNT(*) AS nb_lignes, SUM(chiffre_affaires) AS ca, SUM(marge_brute) AS marge_brute
FROM fact_ventes
GROUP BY source;

-- Exemple de requête OLAP (roll-up par zone et année, slide 57)
SELECT g.zone, d.annee, SUM(f.chiffre_affaires) AS ca, SUM(f.marge_brute) AS marge
FROM fact_ventes f
JOIN dim_geographie g ON g.geo_sk = f.geo_sk
JOIN dim_date       d ON d.date_sk = f.date_sk
WHERE f.statut_commande <> 'Cancelled'
GROUP BY ROLLUP (g.zone, d.annee)
ORDER BY g.zone, d.annee;
