# Projet BI – ce qu'il faut faire, dans l'ordre

Tout a été testé de bout en bout sur une copie locale (Docker) des 2 bases. Les totaux de l'OLAP
tombent pile sur ceux des sources. À l'école, il reste à **exécuter** les scripts, **importer** le flux
NiFi, **remplir les mots de passe** et **faire le Power BI**.

## Ce qu'il y a dans le dossier

| Fichier | À quoi ça sert | Où l'exécuter |
| --- | --- | --- |
| `sql/01_olap_postgres.sql` | Crée l'étoile (fact_ventes + 3 dimensions) et remplit dim_date | PostgreSQL **OLAP** (pgAdmin / CloudBeaver) |
| `sql/02_staging_mysql.sql` | Crée les tables de staging, de référence et de pilotage | **MySQL** du groupe (phpMyAdmin) |
| `sql/03_transform_mysql.sql` | Crée la procédure `sp_transform` (le « T » de l'ETL) | MySQL du groupe, **après** le 02 |
| `sql/04_controles.sql` | Requêtes de vérification après chargement | Chaque partie dans la bonne base |
| `nifi/flux_projet_bi.json` | Le flux NiFi complet, prêt à importer | NiFi du groupe |
| `powerbi/ProjetBI.pbip` | Le projet Power BI complet (modèle + page de rapport) | Power BI Desktop |
| `powerbi/mesures_dax.txt` | Les mesures DAX (déjà dans le projet, pour info) | Power BI Desktop |
| `rapport/rapport.docx` | **Le rapport en Word** (12 pages), à modifier et à rendre | Word |
| `rapport/rapport.tex` + `rapport.pdf` | Le même rapport en LaTeX et sa version compilée | pdflatex (MiKTeX) |
| `test/` | Mini-copies des bases sources, **pour tester chez soi uniquement** | Docker (voir la fin) |

**Le rapport** : `rapport/rapport.docx`, avec les 8 captures (NiFi, contrôles, Power BI) prises sur
l'environnement de test. Il reste à remplacer « Groupe X » et les « Prénom NOM » sur la page de titre.
Si les numéros de page bougent : clic droit sur la table des matières > Mettre à jour les champs.

- **Police** : Latin Modern (« LM Roman 10 »), la même que la version LaTeX. Elle est installée sur ce
  PC ; sur un autre PC, Word la remplacera par une autre police. Pour rendre le rapport, fais
  **Fichier > Enregistrer sous > PDF** : le PDF garde la bonne police partout.
- **Remplacer une capture** : clic droit sur l'image > Modifier l'image > À partir d'un fichier.

---

## Accès du groupe 5 (depuis le réseau du local de cours)

| Outil | Adresse | Sert à | Login |
| --- | --- | --- | --- |
| pgAdmin | `http://10.1.20.51:8458` | BD source classicmodels **et** BD OLAP (serveurs « PgSQL OLTP » et « PgSQL OLAP » déjà déclarés) | `user_ktm@mit.heh.be` |
| CloudBeaver | `http://10.1.20.51:8450` (en HTTP) | Vérifier la BD source dellstore (SQL Server) | `user_ktm` |
| phpMyAdmin | `http://10.1.20.51:8457` (serveur `172.20.0.65`) | Le staging MySQL | `user_ktm` |
| NiFi | `https://10.1.20.51:8445/nifi` (HTTPS, certificat auto-signé : « Paramètres avancés > Continuer ») | L'ETL | `user_ktm` |
| PostgreSQL OLAP | `10.42.7.10:5432` (depuis NiFi) / `10.1.20.51:27171` (depuis ton PC) | La BD OLAP | `user_ktm` |

**Noms des bases du groupe 5** : MySQL `user_ktm` et PostgreSQL OLAP `user_ktm` (une base par
groupe : user_ducati, user_harley, user_ktm…). Mot de passe : celui du groupe, le même partout
(ne le mets dans aucun fichier).

> **Déjà fait le 10/11** : étapes 1 à 4 ci-dessous. Les bases MySQL et OLAP sont créées,
> `ref_pays` contient 262 pays et toutes les zones sont renseignées. Le flux est importé dans NiFi
> avec les services actifs, un ETL complet a tourné sans erreur, et les contrôles sont OK :
> OLAP = sources au centime près, 64 106 lignes de faits. Il te reste Power BI (étape 5).
> Ne refais les étapes 1–3 que si tu veux tout remettre à zéro.

## Étape 1 – BD OLAP (PostgreSQL)

1. Dans pgAdmin, ouvre **Servers > PgSQL OLAP > Databases > user_ktm** (le mot de passe est déjà
   enregistré par le prof).
2. Ouvre un Query Tool sur **ta** base OLAP, colle tout `01_olap_postgres.sql` et exécute-le.
3. Vérifie : la dernière ligne affiche `dim_date | 11323 | 2000-01-01 | 2030-12-31`.

## Étape 2 – BD de staging (MySQL)

1. phpMyAdmin (`http://10.1.20.51:8457`, Server `172.20.0.65`, utilisateur `user_ktm`),
   puis clique sur la base **user_ktm** dans la colonne de gauche, puis l'onglet **SQL**.
2. Colle `02_staging_mysql.sql` et clique sur Exécuter. Tu dois obtenir 17 tables + 1 vue (`v_clients`).
3. Colle `03_transform_mysql.sql` et clique sur Exécuter.
   - En cas d'erreur de syntaxe autour de `DELIMITER` : supprime les 2 lignes `DELIMITER`, mets `//`
     dans le champ « Délimiteur » sous la zone SQL, puis ré-exécute.
4. Vérifie dans l'onglet « Routines » que `sp_transform` existe.

## Étape 3 – NiFi (`https://10.1.20.51:8445/nifi`, groupe 5)

Le navigateur affiche une alerte de certificat (certificat auto-signé de l'école) : « Paramètres
avancés » puis « Continuer vers le site ». Connecte-toi avec `user_ktm` et le mot de passe du groupe.

**Importer le flux**

1. Dans la barre du haut, fais glisser l'icône **Process Group** sur le canevas.
2. Dans la fenêtre, clique sur l'icône d'upload à droite du nom, choisis `nifi/flux_projet_bi.json`,
   puis Add. Le groupe « Projet BI » apparaît, avec 4 sous-groupes et 26 processeurs.

**Remplir les connexions (une seule fois, tout est au même endroit)**

3. Menu ☰ en haut à droite > **Parameter Contexts** > « Projet BI - connexions » > crayon >
   onglet Parameters. Les 4 URL et les 4 utilisateurs sont **déjà remplis** pour le groupe 5
   (`stg_url` = `…172.20.0.65:3306/user_ktm`, `olap_url` = `…10.42.7.10:5432/user_ktm`, `user_ktm` partout).
   Il reste seulement les 4 `*_password` : colle le mot de passe du groupe dans chacun
   (laisse « Set empty string » décoché).
   Clique sur Apply.
4. Entre dans « Projet BI » (double-clic), clic sur le fond, puis l'engrenage (palette Operate) >
   **Controller Services**. Active les 6 services avec l'éclair : 4 DBCP + AvroReader + AvroRecordSetWriter.
   S'il y a un triangle jaune, survole-le : c'est en général un mot de passe ou une URL.

> Si l'import ne marche pas (version de NiFi trop ancienne), refais le flux à la main avec le
> tableau « Configuration des processeurs » du rapport : mêmes processeurs, mêmes valeurs.

**Premier lancement (pour la démo et les captures)**

5. Dans chaque sous-groupe, clic droit sur chaque **PutDatabaseRecord** et sur le **PutSQL** > Start
   (ils attendent les données).
6. Groupes 1 et 2 : clic droit sur chaque **Extract …** (QueryDatabaseTableRecord) > **Run Once**.
   Attends que les files d'attente retombent à 0.
7. Groupe 3 : clic droit sur « Déclencheur transform » > Run Once.
8. Groupe 4 : Run Once sur « Read dw_dim_produit » et « Read dw_dim_geographie ». Quand c'est fini,
   Run Once sur « Read dw_fact_ventes ».
9. La file **ERREURS** de chaque groupe doit rester vide. En cas de problème, un carré rouge apparaît
   en haut à droite du processeur : survole-le pour lire l'erreur.

**Mode « production » (chaque nuit, automatique)** : sélectionne tout le groupe « Projet BI » >
Start. Les Extract partent à 02:00, le Transform à 02:15, le Load des dimensions à 02:30 et celui
des faits à 02:35.

## Étape 4 – Vérifier

Exécute `04_controles.sql`, chaque partie dans la bonne base (A dans classicmodels, B dans dellstore,
C dans MySQL, D dans l'OLAP). Le CA et la marge de l'OLAP doivent être **identiques** à ceux des sources.
Fais une capture de cette comparaison (`captures/controles.png`) : les profs adorent.

Côté MySQL, `SELECT * FROM etl_journal;` montre chaque exécution de la transformation (OK ou ERREUR).

## Étape 5 – Power BI Desktop

Tout est déjà construit dans **`powerbi/ProjetBI.pbip`** : connexion, 3 relations, table de dates,
hiérarchies, 5 mesures DAX et la page « Analyse des ventes » (4 segments, 4 cartes, 3 graphiques,
1 matrice). Testé avec Power BI Desktop 2.159.

1. Double-clique sur `powerbi/ProjetBI.pbip` (Power BI Desktop s'ouvre).
2. **Accueil > Transformer les données > Modifier les paramètres** :
   - `Serveur` = `10.1.20.51:27171` (déjà mis ; pour la base de test Docker chez toi : `localhost:15432`) ;
   - `BaseOLAP` = `user_ktm` (déjà mis).
3. Clique sur **Actualiser** (ou « Actualiser maintenant » dans le bandeau). Identifiants : onglet
   « Base de données », utilisateur `user_ktm` et le mot de passe du groupe.
4. Erreur « Le certificat distant n'est pas valide » ? Le PostgreSQL de l'école a un certificat
   auto-signé. Va dans **Fichier > Options et paramètres > Paramètres de la source de données**, choisis
   `10.1.20.51:27171;user_ktm` > **Modifier les autorisations**, décoche **Chiffrer les connexions** > OK,
   puis **Appliquer les modifications** et **Actualiser**. (Déjà fait sur ton PC le 10/11.)
5. Les visuels se remplissent (CA 16 006 097, marge 6 307 401). Enregistre (Ctrl+S).

Les captures Power BI du rapport ont été refaites le 10/11 sur les vraies données de l'école.

---

## Si ça plante

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| DBCP invalide, « Cannot create PoolableConnectionFactory » | URL, login ou mot de passe faux | Revérifie le Parameter Context |
| MySQL : « Public Key Retrieval is not allowed » | Sécurité de MySQL 8 | Ajoute `?allowPublicKeyRetrieval=true&useSSL=false` à la fin de `stg_url` |
| PutSQL : « PROCEDURE sp_transform does not exist » | Script 03 non exécuté, ou dans une autre base | Ré-exécute le 03 dans la base de `stg_url` |
| fact_ventes : violation de clé étrangère | Faits chargés avant les dimensions | Run Once sur les 2 « Read dw_dim_* », puis sur « Read dw_fact_ventes » |
| Accents abîmés (« AmÃ©rique ») | Encodage | Les scripts 02 et 03 commencent par `SET NAMES utf8mb4;` : ré-exécute-les |
| Un pays apparaît en zone « Autre » | Pays absent de `ref_pays` | `INSERT INTO ref_pays VALUES ('NOM EN MAJUSCULES','Nom','XX','Zone');` puis relance Transform et Load |
| Tout recharger depuis zéro | — | NiFi : clic droit sur chaque QueryDatabaseTableRecord > View state > Clear state. MySQL : `UPDATE etl_controle SET derniere_execution = NULL;` |

## Ce que le prof va probablement demander à l'oral

- **Pourquoi une étoile et pas un flocon ?** Moins de jointures et des requêtes plus simples (slide 74).
  La catégorie est recopiée dans dim_produit : c'est voulu, la redondance est OK en OLAP (slide 66).
- **Pourquoi un staging MySQL ?** Pour transformer sans toucher aux bases de prod, et ne jamais écrire
  de données fausses directement dans le DW (slide 43).
- **Comment est calculée la marge de dellstore ?** dellstore n'a pas de prix d'achat : on estime le
  coût à 65 % du prix. C'est un paramètre (`etl_parametre`), modifiable sans toucher au code.
- **C'est quoi le CDC chez vous ?** On ne relit que les lignes dont `last_update` a augmenté
  (classicmodels : colonne `last_update` ; dellstore : tables `hist_*`). Dans le staging, la colonne
  `etl_maj` ne bouge que si une valeur change vraiment. Test : 0 ligne envoyée quand rien ne change,
  7 lignes après 5 modifications.
- **Vous l'avez montré sur nos serveurs ?** Oui (bonus, 10/11). Les sources sont partagées et en
  lecture seule, mais le prof y ajoute des lots (le dernier le 09/11 à 11:09 : 8 commandes / 40 lignes
  par source). On a remis notre entrepôt à l'état d'avant ce lot, recalé le repère NiFi juste avant
  (`initial.maxvalue.last_update`), relancé l'ETL : seul le lot est passé (40 + 40 ventes, 2,3 s)
  et l'OLAP est revenu pile aux totaux des sources. Captures `nifi_cdc.png` et `cdc_ecole.png`.
- **Démo en direct à l'oral** : au prochain lot du prof, fais Run Once sur les Extract, puis
  « Déclencheur transform », puis les 3 « Read dw_* ». Dans phpMyAdmin,
  `SELECT * FROM etl_journal ORDER BY id DESC;` montre que seules les nouvelles ventes ont été traitées.

## Tester chez toi (optionnel)

Les conteneurs Docker de test sont arrêtés sur ce PC : `bi-pg`, `bi-mysql`, `bi-mssql` et `bi-nifi`.
Pour les relancer :

```bash
docker start bi-pg bi-mysql bi-mssql bi-nifi
```

NiFi (avec le flux déjà importé et configuré) s'ouvre alors sur http://localhost:18080/nifi.
MySQL écoute sur localhost:13306 (root / test), PostgreSQL sur localhost:15432 (postgres / test).
