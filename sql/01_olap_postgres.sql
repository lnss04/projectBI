-- =====================================================================
--  PROJET BI - 01 : BD OLAP (PostgreSQL OLAP : 10.42.7.10:5432 / 10.1.20.51:27171)
--  Modèle en ÉTOILE : 1 table de faits + 3 dimensions
--
--     dim_date ─────┐
--     dim_produit ──┼── fact_ventes   (grain = 1 ligne de commande)
--     dim_geographie┘
--
--  À exécuter UNE fois dans la base OLAP du groupe (pgAdmin / CloudBeaver).
--  dim_date est générée ici par SQL (dimension statique, slide 68 & 83).
--  dim_produit, dim_geographie et fact_ventes sont remplies par NiFi.
-- =====================================================================

DROP TABLE IF EXISTS fact_ventes;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_produit;
DROP TABLE IF EXISTS dim_geographie;

-- ---------------------------------------------------------------------
-- DIMENSION DATE  (clé "intelligente" AAAAMMJJ, ex : 20040315)
-- Ordre des colonnes = hiérarchie Année > Trimestre > Mois > Jour (slide 69)
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_sk            INTEGER      PRIMARY KEY,          -- AAAAMMJJ
    annee              SMALLINT     NOT NULL,
    trimestre          SMALLINT     NOT NULL,
    mois               SMALLINT     NOT NULL,
    jour               SMALLINT     NOT NULL,
    date_complete      DATE         NOT NULL UNIQUE,
    libelle_trimestre  VARCHAR(7)   NOT NULL,             -- 'T1 2004'
    annee_mois         CHAR(7)      NOT NULL,             -- '2004-03'
    nom_mois           VARCHAR(10)  NOT NULL,             -- 'Mars'
    jour_semaine       SMALLINT     NOT NULL,             -- 1 = lundi ... 7 = dimanche
    nom_jour           VARCHAR(10)  NOT NULL,
    est_weekend        BOOLEAN      NOT NULL
);

INSERT INTO dim_date
SELECT  TO_CHAR(d, 'YYYYMMDD')::INTEGER,
        EXTRACT(YEAR    FROM d)::SMALLINT,
        EXTRACT(QUARTER FROM d)::SMALLINT,
        EXTRACT(MONTH   FROM d)::SMALLINT,
        EXTRACT(DAY     FROM d)::SMALLINT,
        d::DATE,
        'T' || EXTRACT(QUARTER FROM d) || ' ' || EXTRACT(YEAR FROM d),
        TO_CHAR(d, 'YYYY-MM'),
        (ARRAY['Janvier','Février','Mars','Avril','Mai','Juin','Juillet',
               'Août','Septembre','Octobre','Novembre','Décembre'])[EXTRACT(MONTH FROM d)],
        EXTRACT(ISODOW FROM d)::SMALLINT,
        (ARRAY['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'])[EXTRACT(ISODOW FROM d)],
        EXTRACT(ISODOW FROM d) IN (6, 7)
FROM generate_series(DATE '2000-01-01', DATE '2030-12-31', INTERVAL '1 day') AS d;

-- ---------------------------------------------------------------------
-- DIMENSION PRODUIT  (article + catégorie dénormalisés = étoile, pas flocon)
-- Hiérarchie : Univers > Catégorie > Article.  SCD type 1 (écrasement).
-- ---------------------------------------------------------------------
CREATE TABLE dim_produit (
    produit_sk      INTEGER        PRIMARY KEY,           -- clé technique (générée dans le staging)
    univers         VARCHAR(30)    NOT NULL,              -- 'Modèles réduits' / 'DVD'
    categorie       VARCHAR(50)    NOT NULL,              -- productline / categoryname
    libelle         VARCHAR(100)   NOT NULL,              -- nom de l'article
    code_produit    VARCHAR(20)    NOT NULL,              -- clé métier dans la source
    source          VARCHAR(20)    NOT NULL,              -- 'classicmodels' / 'dellstore'
    fournisseur     VARCHAR(60),
    prix_catalogue  NUMERIC(10,2),
    cout_unitaire   NUMERIC(10,2),
    etl_maj         TIMESTAMP(3),                         -- date de dernière modif. par l'ETL
    UNIQUE (source, code_produit)
);

-- ---------------------------------------------------------------------
-- DIMENSION GÉOGRAPHIE  (localisation du client, anonymisée : pas de nom/adresse)
-- Hiérarchie : Zone > Pays > État/Province > Ville
-- ---------------------------------------------------------------------
CREATE TABLE dim_geographie (
    geo_sk          INTEGER        PRIMARY KEY,
    zone            VARCHAR(30)    NOT NULL,              -- 'Europe', 'Amérique du Nord', ...
    pays            VARCHAR(50)    NOT NULL,
    etat_province   VARCHAR(50)    NOT NULL,
    ville           VARCHAR(50)    NOT NULL,
    code_pays       CHAR(2),                              -- ISO-2 (pratique pour la carte Power BI)
    etl_maj         TIMESTAMP(3),
    UNIQUE (pays, etat_province, ville)
);

-- ---------------------------------------------------------------------
-- TABLE DE FAITS  (grain : 1 ligne de commande)
-- Mesures additives : quantite, chiffre_affaires, cout_achat, marge_brute
-- Dimensions dégénérées (slide 80) : source, num_commande, ligne_source, statut
-- ---------------------------------------------------------------------
CREATE TABLE fact_ventes (
    vente_sk          BIGINT         PRIMARY KEY,
    date_sk           INTEGER        NOT NULL REFERENCES dim_date(date_sk),
    produit_sk        INTEGER        NOT NULL REFERENCES dim_produit(produit_sk),
    geo_sk            INTEGER        NOT NULL REFERENCES dim_geographie(geo_sk),
    quantite          INTEGER        NOT NULL,
    prix_unitaire     NUMERIC(10,2)  NOT NULL,
    cout_unitaire     NUMERIC(10,2)  NOT NULL,
    chiffre_affaires  NUMERIC(12,2)  NOT NULL,            -- quantite * prix_unitaire
    cout_achat        NUMERIC(12,2)  NOT NULL,            -- quantite * cout_unitaire
    marge_brute       NUMERIC(12,2)  NOT NULL,            -- CA - cout_achat
    source            VARCHAR(20)    NOT NULL,
    num_commande      INTEGER        NOT NULL,
    ligne_source      VARCHAR(20)    NOT NULL,
    statut_commande   VARCHAR(20)    NOT NULL,
    etl_maj           TIMESTAMP(3),
    UNIQUE (source, num_commande, ligne_source)
);

-- Index sur les clés étrangères (accélère les JOIN ... WHERE des requêtes OLAP)
CREATE INDEX ix_fact_date    ON fact_ventes (date_sk);
CREATE INDEX ix_fact_produit ON fact_ventes (produit_sk);
CREATE INDEX ix_fact_geo     ON fact_ventes (geo_sk);

-- Vérification rapide
SELECT 'dim_date' AS table_, COUNT(*) AS nb_lignes, MIN(date_complete)::TEXT AS min_, MAX(date_complete)::TEXT AS max_ FROM dim_date;
