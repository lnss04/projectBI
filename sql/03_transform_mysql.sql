-- =====================================================================
--  PROJET BI - 03 : TRANSFORMATION (procédure stockée MySQL)
--  Appelée par NiFi (GenerateFlowFile "CALL sp_transform();" -> PutSQL)
--
--  Ce qu'elle fait (le "T" de l'ETL) :
--   1. dw_dim_produit    : fusion des produits des 2 sources (SCD type 1)
--   2. dw_dim_geographie : géographie clients uniformisée (pays, zone)
--   3. dw_fact_ventes    : calcul CA / coût / marge brute par ligne de commande
--  -> uniquement les lignes nouvelles ou modifiées depuis le dernier passage
--     (watermark etl_controle + colonne etl_maj = Change Data Capture).
--
--  À exécuter UNE fois dans phpMyAdmin (onglet SQL) après le script 02.
--  Dans phpMyAdmin, mettre le champ "Délimiteur" sur  //  OU garder les
--  lignes DELIMITER ci-dessous (elles fonctionnent aussi en ligne de commande).
-- =====================================================================

SET NAMES utf8mb4;   -- les textes 'Modèles réduits', 'Non renseigné' sont stockés dans la procédure

DROP PROCEDURE IF EXISTS sp_transform;

DELIMITER //

CREATE PROCEDURE sp_transform()
BEGIN
    DECLARE v_debut      DATETIME(3);
    DECLARE v_wm         DATETIME(3);
    DECLARE v_taux_def   DECIMAL(10,4);
    DECLARE v_id_journal INT;
    DECLARE v_nb_prod, v_nb_geo, v_nb_cm, v_nb_ds INT DEFAULT 0;

    -- En cas d'erreur : on annule tout et on renvoie l'erreur à NiFi
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        UPDATE etl_journal SET fin = NOW(3), statut = 'ERREUR' WHERE id = v_id_journal;
        RESIGNAL;
    END;

    SET v_debut = NOW(3);
    SELECT COALESCE(derniere_execution, '1900-01-01') INTO v_wm
      FROM etl_controle WHERE etape = 'transform';
    SELECT valeur INTO v_taux_def FROM etl_parametre WHERE cle = 'taux_cout_dellstore';

    INSERT INTO etl_journal (debut, watermark_utilise, statut) VALUES (v_debut, v_wm, 'EN COURS');
    SET v_id_journal = LAST_INSERT_ID();

    START TRANSACTION;

    -- -----------------------------------------------------------------
    -- 1. DIMENSION PRODUIT (SCD type 1 : on écrase avec la dernière valeur)
    -- -----------------------------------------------------------------
    INSERT INTO dw_dim_produit (univers, categorie, libelle, code_produit, source,
                                fournisseur, prix_catalogue, cout_unitaire)
    SELECT 'Modèles réduits',
           TRIM(p.productline),
           TRIM(p.productname),
           TRIM(p.productcode),
           'classicmodels',
           TRIM(p.productvendor),
           p.msrp,
           p.buyprice                                  -- vrai prix d'achat
    FROM stg_cm_products p
    ON DUPLICATE KEY UPDATE
        univers = VALUES(univers), categorie = VALUES(categorie), libelle = VALUES(libelle),
        fournisseur = VALUES(fournisseur), prix_catalogue = VALUES(prix_catalogue),
        cout_unitaire = VALUES(cout_unitaire);
    SET v_nb_prod = ROW_COUNT();

    INSERT INTO dw_dim_produit (univers, categorie, libelle, code_produit, source,
                                fournisseur, prix_catalogue, cout_unitaire)
    SELECT 'DVD',
           COALESCE(TRIM(c.categoryname), CONCAT('Catégorie ', p.category)),
           TRIM(p.title),
           CAST(p.prod_id AS CHAR),
           'dellstore',
           'Dell DVD Store',
           p.price,
           ROUND(p.price * COALESCE(t.taux_cout, v_taux_def), 2)   -- coût ESTIMÉ (pas de prix d'achat dans dellstore)
    FROM stg_ds_products p
    LEFT JOIN stg_ds_categories c ON c.category = p.category
    LEFT JOIN ref_taux_cout_ds  t ON t.category = p.category
    ON DUPLICATE KEY UPDATE
        univers = VALUES(univers), categorie = VALUES(categorie), libelle = VALUES(libelle),
        fournisseur = VALUES(fournisseur), prix_catalogue = VALUES(prix_catalogue),
        cout_unitaire = VALUES(cout_unitaire);
    SET v_nb_prod = v_nb_prod + ROW_COUNT();

    -- -----------------------------------------------------------------
    -- 2. DIMENSION GÉOGRAPHIE (une ligne par pays / état / ville distinct)
    -- -----------------------------------------------------------------
    INSERT INTO dw_dim_geographie (zone, pays, etat_province, ville, code_pays)
    SELECT DISTINCT zone, pays, etat_province, ville, code_pays
    FROM v_clients
    ON DUPLICATE KEY UPDATE zone = VALUES(zone), code_pays = VALUES(code_pays);
    SET v_nb_geo = ROW_COUNT();

    -- Table de correspondance client -> geo_sk (temporaire, pour les faits)
    DROP TEMPORARY TABLE IF EXISTS tmp_client_geo;
    CREATE TEMPORARY TABLE tmp_client_geo (
        source    VARCHAR(20) NOT NULL,
        client_id INT         NOT NULL,
        geo_sk    INT         NOT NULL,
        PRIMARY KEY (source, client_id)
    );
    INSERT INTO tmp_client_geo
    SELECT c.source, c.client_id, g.geo_sk
    FROM v_clients c
    JOIN dw_dim_geographie g
      ON g.pays = c.pays AND g.etat_province = c.etat_province AND g.ville = c.ville;

    -- -----------------------------------------------------------------
    -- 3a. FAITS classicmodels : CA = qté x priceeach ; coût = qté x buyprice
    --     On ne traite que les lignes nouvelles/modifiées (CDC) ou absentes.
    -- -----------------------------------------------------------------
    INSERT INTO dw_fact_ventes (date_sk, produit_sk, geo_sk, quantite, prix_unitaire, cout_unitaire,
                                chiffre_affaires, cout_achat, marge_brute,
                                source, num_commande, ligne_source, statut_commande)
    SELECT CAST(DATE_FORMAT(o.orderdate, '%Y%m%d') AS UNSIGNED),
           dp.produit_sk,
           cg.geo_sk,
           od.quantityordered,
           od.priceeach,
           dp.cout_unitaire,
           ROUND(od.quantityordered * od.priceeach, 2),
           ROUND(od.quantityordered * dp.cout_unitaire, 2),
           ROUND(od.quantityordered * od.priceeach, 2) - ROUND(od.quantityordered * dp.cout_unitaire, 2),
           'classicmodels',
           od.ordernumber,
           od.productcode,
           COALESCE(NULLIF(TRIM(o.status), ''), 'Non renseigné')
    FROM stg_cm_orderdetails od
    JOIN stg_cm_orders   o  ON o.ordernumber = od.ordernumber
    JOIN tmp_client_geo  cg ON cg.source = 'classicmodels' AND cg.client_id = o.customernumber
    JOIN dw_dim_produit  dp ON dp.source = 'classicmodels' AND dp.code_produit = od.productcode
    WHERE od.etl_maj >= v_wm
       OR o.etl_maj  >= v_wm
       OR NOT EXISTS (SELECT 1 FROM dw_fact_ventes f
                      WHERE f.source = 'classicmodels'
                        AND f.num_commande = od.ordernumber
                        AND f.ligne_source = od.productcode)
    ON DUPLICATE KEY UPDATE
        date_sk = VALUES(date_sk), produit_sk = VALUES(produit_sk), geo_sk = VALUES(geo_sk),
        quantite = VALUES(quantite), prix_unitaire = VALUES(prix_unitaire),
        cout_unitaire = VALUES(cout_unitaire), chiffre_affaires = VALUES(chiffre_affaires),
        cout_achat = VALUES(cout_achat), marge_brute = VALUES(marge_brute),
        statut_commande = VALUES(statut_commande);
    SET v_nb_cm = ROW_COUNT();

    -- -----------------------------------------------------------------
    -- 3b. FAITS dellstore : CA = qté x price ; coût = qté x coût estimé
    -- -----------------------------------------------------------------
    INSERT INTO dw_fact_ventes (date_sk, produit_sk, geo_sk, quantite, prix_unitaire, cout_unitaire,
                                chiffre_affaires, cout_achat, marge_brute,
                                source, num_commande, ligne_source, statut_commande)
    SELECT CAST(DATE_FORMAT(COALESCE(o.orderdate, ol.orderdate), '%Y%m%d') AS UNSIGNED),
           dp.produit_sk,
           cg.geo_sk,
           ol.quantity,
           dp.prix_catalogue,
           dp.cout_unitaire,
           ROUND(ol.quantity * dp.prix_catalogue, 2),
           ROUND(ol.quantity * dp.cout_unitaire, 2),
           ROUND(ol.quantity * dp.prix_catalogue, 2) - ROUND(ol.quantity * dp.cout_unitaire, 2),
           'dellstore',
           ol.orderid,
           CAST(ol.orderlineid AS CHAR),
           'Non renseigné'
    FROM stg_ds_orderlines ol
    JOIN stg_ds_orders   o  ON o.orderid = ol.orderid
    JOIN tmp_client_geo  cg ON cg.source = 'dellstore' AND cg.client_id = o.customerid
    JOIN dw_dim_produit  dp ON dp.source = 'dellstore' AND dp.code_produit = CAST(ol.prod_id AS CHAR)
    WHERE ol.etl_maj >= v_wm
       OR o.etl_maj  >= v_wm
       OR NOT EXISTS (SELECT 1 FROM dw_fact_ventes f
                      WHERE f.source = 'dellstore'
                        AND f.num_commande = ol.orderid
                        AND f.ligne_source = CAST(ol.orderlineid AS CHAR))
    ON DUPLICATE KEY UPDATE
        date_sk = VALUES(date_sk), produit_sk = VALUES(produit_sk), geo_sk = VALUES(geo_sk),
        quantite = VALUES(quantite), prix_unitaire = VALUES(prix_unitaire),
        cout_unitaire = VALUES(cout_unitaire), chiffre_affaires = VALUES(chiffre_affaires),
        cout_achat = VALUES(cout_achat), marge_brute = VALUES(marge_brute),
        statut_commande = VALUES(statut_commande);
    SET v_nb_ds = ROW_COUNT();

    -- -----------------------------------------------------------------
    -- 4. Fin : nouveau watermark + journal
    -- -----------------------------------------------------------------
    UPDATE etl_controle SET derniere_execution = v_debut WHERE etape = 'transform';

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_client_geo;

    UPDATE etl_journal
       SET fin = NOW(3), nb_produits = v_nb_prod, nb_geo = v_nb_geo,
           nb_ventes_cm = v_nb_cm, nb_ventes_ds = v_nb_ds, statut = 'OK'
     WHERE id = v_id_journal;
END //

DELIMITER ;

-- Test manuel :
-- CALL sp_transform();
-- SELECT * FROM etl_journal ORDER BY id DESC LIMIT 5;
