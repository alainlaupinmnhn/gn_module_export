SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

BEGIN;
DROP SCHEMA IF EXISTS gn_exports CASCADE;
CREATE SCHEMA gn_exports;
COMMIT;

SET search_path = gn_exports, pg_catalog;

BEGIN;
-- Table listant les exports
CREATE TABLE gn_exports.t_exports
(
    id SERIAL NOT NULL PRIMARY KEY,
    label text COLLATE pg_catalog."default" NOT NULL,
    schema_name text COLLATE pg_catalog."default" NOT NULL,
    view_name text COLLATE pg_catalog."default" NOT NULL,
    "desc" text COLLATE pg_catalog."default",
    geometry_field character varying(255),
    geometry_srid INTEGER,
    public boolean NOT NULL default FALSE,
    id_licence INTEGER NOT NULL,
    CONSTRAINT uniq_label UNIQUE (label)
);

COMMENT ON TABLE gn_exports.t_exports IS 'This table is used to declare views intended for export.';
COMMENT ON COLUMN gn_exports.t_exports.id IS 'Internal value for primary keys';
COMMENT ON COLUMN gn_exports.t_exports.schema_name IS 'Schema name where the view is stored';
COMMENT ON COLUMN gn_exports.t_exports.view_name IS 'The view name';
COMMENT ON COLUMN gn_exports.t_exports.label IS 'Export name to display';
COMMENT ON COLUMN gn_exports.t_exports."desc" IS 'Short or long text to explain the export and/or is content';
COMMENT ON COLUMN gn_exports.t_exports.geometry_field IS 'Name of the geometry field if the export is spatial';
COMMENT ON COLUMN gn_exports.t_exports.geometry_srid IS 'SRID of the geometry';
COMMENT ON COLUMN gn_exports.t_exports.public IS 'Data access';
COMMENT ON COLUMN gn_exports.t_exports.id_licence IS 'Licence id';

-----------
--LICENCE--
-----------

-- Liste des licences
CREATE TABLE gn_exports.t_licences (
    id_licence SERIAL NOT NULL,
    name_licence varchar(100) NOT NULL,
    url_licence varchar(500) NOT NULL
);
COMMENT ON TABLE gn_exports.t_licences IS 'This table is used to declare the licences list.';

ALTER TABLE ONLY gn_exports.t_licences
    ADD CONSTRAINT pk_gn_exports_t_licences PRIMARY KEY (id_licence);
ALTER TABLE ONLY gn_exports.t_exports
    ADD CONSTRAINT fk_gn_exports_t_exports_id_licence FOREIGN KEY (id_licence) REFERENCES gn_exports.t_licences (id_licence);

-- Licences par défaut
INSERT INTO gn_exports.t_licences (name_licence, url_licence) VALUES
    ('Creative Commons Attribution 1.0 Generic', 'https://spdx.org/licenses/CC-BY-1.0.html'),
    ('ODC Open Database License v1.0', 'https://spdx.org/licenses/ODbL-1.0.html#licenseText'),
    ('Licence Ouverte/Open Licence Version 2.0', 'https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf');


---------
--ROLES--
---------

CREATE TABLE gn_exports.cor_exports_roles (
    id_export integer NOT NULL,
    id_role integer NOT NULL
);
ALTER TABLE ONLY gn_exports.cor_exports_roles
    ADD CONSTRAINT cor_exports_roles_pkey PRIMARY KEY (id_export, id_role);

ALTER TABLE ONLY gn_exports.cor_exports_roles
    ADD CONSTRAINT fk_cor_exports_roles_id_export FOREIGN KEY (id_export) REFERENCES gn_exports.t_exports(id);

ALTER TABLE ONLY gn_exports.cor_exports_roles
    ADD CONSTRAINT fk_cor_exports_roles_id_role FOREIGN KEY (id_role) REFERENCES utilisateurs.t_roles(id_role) ON UPDATE CASCADE;


--------
--LOGS--
--------

CREATE TABLE gn_exports.t_exports_logs
(
    id SERIAL NOT NULL PRIMARY KEY,
    id_role integer NOT NULL,
    id_export integer,
    format character varying(10) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status numeric DEFAULT '-2'::integer,
    log text,
    CONSTRAINT fk_export FOREIGN KEY (id_export)
        REFERENCES gn_exports.t_exports (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT fk_user FOREIGN KEY (id_role)
        REFERENCES utilisateurs.t_roles (id_role) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

COMMENT ON TABLE gn_exports.t_exports_logs IS 'This table is used to log all the realised exports.';
COMMENT ON COLUMN gn_exports.t_exports_logs.id_role IS 'Role who realize export';
COMMENT ON COLUMN gn_exports.t_exports_logs.id_export IS 'Export type';
COMMENT ON COLUMN gn_exports.t_exports_logs.format IS 'The exported format (csv, json, shp, geojson)';
COMMENT ON COLUMN gn_exports.t_exports_logs.start_time IS 'When the export process start';
COMMENT ON COLUMN gn_exports.t_exports_logs.end_time IS 'When the export process finish';
COMMENT ON COLUMN gn_exports.t_exports_logs.status IS 'Status of the process : 1 ok: -2 error';
COMMENT ON COLUMN gn_exports.t_exports_logs.log IS 'Holds export failure message';

-- View to list Exports LOGS with users names and exports labels
CREATE VIEW gn_exports.v_exports_logs AS
 SELECT r.nom_role ||' '||r.prenom_role AS utilisateur, e.label, l.format, l.start_time, l.end_time, l.status, l.log
 FROM gn_exports.t_exports_logs l
 JOIN utilisateurs.t_roles r ON r.id_role = l.id_role
 JOIN gn_exports.t_exports e ON e.id = l.id_export
 ORDER BY start_time;

COMMIT;


---------------------
--EXPORTS PLANIFIES--
---------------------

CREATE TABLE gn_exports.t_export_schedules (
    id_export_schedule SERIAL NOT NULL,
    id_export integer NOT NULL,
    frequency integer NOT NULL,
    format character varying(10) NOT NULL
);
ALTER TABLE ONLY gn_exports.t_export_schedules
    ADD CONSTRAINT t_export_schedules_pkey PRIMARY KEY (id_export_schedule);

ALTER TABLE ONLY gn_exports.t_export_schedules
    ADD CONSTRAINT fk_t_export_schedules_id_export FOREIGN KEY (id_export) REFERENCES gn_exports.t_exports(id);

COMMENT ON COLUMN gn_exports.t_export_schedules."frequency" IS 'Fréquence de remplacement du fichier en jour';


---------
--VIEWS--
---------

-- Vue par défaut d'export des données de la synthèse au format SINP
CREATE OR REPLACE VIEW gn_exports.v_synthese_sinp AS
 WITH jdd_acteurs AS (  
 SELECT
    d.id_dataset,
    string_agg(DISTINCT concat(COALESCE(orga.nom_organisme, ((roles.nom_role::text || ' '::text) || roles.prenom_role::text)::character varying), ' : ', nomencl.label_default), ' | '::text) AS acteurs
   FROM gn_meta.t_datasets d
     JOIN gn_meta.cor_dataset_actor act ON act.id_dataset = d.id_dataset
     JOIN ref_nomenclatures.t_nomenclatures nomencl ON nomencl.id_nomenclature = act.id_nomenclature_actor_role
     LEFT JOIN utilisateurs.bib_organismes orga ON orga.id_organisme = act.id_organism
     LEFT JOIN utilisateurs.t_roles roles ON roles.id_role = act.id_role
  GROUP BY d.id_dataset
)
 SELECT s.id_synthese AS "ID_synthese",
    s.entity_source_pk_value AS "ID_source",
    s.unique_id_sinp AS "ID_perm_SINP",
    s.unique_id_sinp_grp AS "ID_perm_GRP_SINP",
    s.date_min AS "Date_debut",
    s.date_max AS "Date_fin",
    t.cd_nom AS "CD_nom",
    t.cd_ref AS "CD_ref",
    s.meta_v_taxref AS "Version_Taxref",
    s.nom_cite AS "Nom_cite",
    t.nom_valide AS "Nom_valide",
    t.regne AS "Regne",
    t.group1_inpn AS "Group1_INPN",
    t.group2_inpn AS "Group2_INPN",
    t.classe AS "Classe",
    t.ordre AS "Ordre",
    t.famille AS "Famille",
    t.id_rang AS "Rang_taxo",
    s.count_min AS "Nombre_min",
    s.count_max AS "Nombre_max",
    s.altitude_min AS "Altitude_min",
    s.altitude_max AS "Altitude_max",
    s.observers AS "Observateurs",
    s.determiner AS "Determinateur",
    s.validator AS "Validateur",
    s.sample_number_proof AS "Numero_preuve",
    s.digital_proof AS "Preuve_numerique",
    s.non_digital_proof AS "Preuve_non_numerique",
    s.the_geom_4326 AS geom,
    s.comment_context AS "Comment_releve",
    s.comment_description AS "Comment_occurrence",
    s.meta_create_date AS "Date_creation",
    s.meta_update_date AS "Date_modification",
    COALESCE(s.meta_update_date, s.meta_create_date) AS "Derniere_action",
    d.unique_dataset_id AS "JDD_UUID",
    d.dataset_name AS "JDD_nom",
    jdd_acteurs.acteurs AS "JDD_acteurs",
    af.unique_acquisition_framework_id AS "CA_UUID",
    af.acquisition_framework_name AS "CA_nom",
    public.st_astext(s.the_geom_4326) AS "WKT_4326",
    public.ST_x(s.the_geom_point) AS "X_centroid_4326",
    public.ST_y(s.the_geom_point) AS "Y_centroid_4326",
    n1.label_default AS "Nature_objet_geo",
    n2.label_default AS "Methode_regroupement",
    n3.label_default AS "Methode_obs",
    n4.label_default AS "Technique_obs",
    n5.label_default AS "Statut_biologique",
    n6.label_default AS "Etat_biologique",
    n7.label_default AS "Naturalite",
    n8.label_default AS "Preuve_existante",
    n9.label_default AS "Precision_diffusion",
    n10.label_default AS "Stade_vie",
    n11.label_default AS "Sexe",
    n12.label_default AS "Objet_denombrement",
    n13.label_default AS "Type_denombrement",
    n14.label_default AS "Niveau_sensibilite",
    n15.label_default AS "Statut_observation",
    n16.label_default AS "Floutage_DEE",
    n17.label_default AS "Statut_source",
    n18.label_default AS "Type_info_geo",
    n19.label_default AS "Methode_determination"
   FROM gn_synthese.synthese s
     JOIN taxonomie.taxref t ON t.cd_nom = s.cd_nom
     JOIN gn_meta.t_datasets d ON d.id_dataset = s.id_dataset
     JOIN jdd_acteurs ON jdd_acteurs.id_dataset = s.id_dataset
     JOIN gn_meta.t_acquisition_frameworks af ON d.id_acquisition_framework = af.id_acquisition_framework
     JOIN gn_synthese.t_sources sources ON sources.id_source = s.id_source
     LEFT JOIN ref_nomenclatures.t_nomenclatures n1 ON s.id_nomenclature_geo_object_nature = n1.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n2 ON s.id_nomenclature_grp_typ = n2.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n3 ON s.id_nomenclature_obs_meth = n3.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n4 ON s.id_nomenclature_obs_technique = n4.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n5 ON s.id_nomenclature_bio_status = n5.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n6 ON s.id_nomenclature_bio_condition = n6.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n7 ON s.id_nomenclature_naturalness = n7.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n8 ON s.id_nomenclature_exist_proof = n8.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n9 ON s.id_nomenclature_diffusion_level = n9.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n10 ON s.id_nomenclature_life_stage = n10.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n11 ON s.id_nomenclature_sex = n11.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n12 ON s.id_nomenclature_obj_count = n12.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n13 ON s.id_nomenclature_type_count = n13.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n14 ON s.id_nomenclature_sensitivity = n14.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n15 ON s.id_nomenclature_observation_status = n15.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n16 ON s.id_nomenclature_blurring = n16.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n17 ON s.id_nomenclature_source_status = n17.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n18 ON s.id_nomenclature_info_geo_type = n18.id_nomenclature
     LEFT JOIN ref_nomenclatures.t_nomenclatures n19 ON s.id_nomenclature_determination_method = n19.id_nomenclature
;

COMMENT ON COLUMN gn_exports.v_synthese_sinp."ID_synthese" IS 'Identifiant de la donnée dans la table synthese';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."ID_source" IS 'Identifiant de la donnée dans la table source';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."ID_perm_SINP" IS 'Identifiant permanent de l''occurrence';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."ID_perm_GRP_SINP" IS 'Identifiant permanent du regroupement';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Date_debut" IS 'Date du jour, dans le système local de l''observation dans le système grégorien. En cas d’imprécision, cet attribut représente la date la plus ancienne de la période d''imprécision.';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Date_fin" IS 'Date du jour, dans le système local de l''observation dans le système grégorien. En cas d’imprécision, cet attribut représente la date la plus récente de la période d''imprécision.';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."CD_nom" IS 'Identifiant Taxref du nom de l''objet observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."CD_ref" IS 'Identifiant Taxref du taxon correspondant à l''objet observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Version_Taxref" IS 'Version de Taxref utilisée';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Nom_cite" IS 'Nom de l''objet utilisé dans la donnée source';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Nom_valide" IS 'Nom valide de l''objet observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Regne" IS 'Règne de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Group1_INPN" IS 'Groupe INPN (1) de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Group2_INPN" IS 'Groupe INPN (2) de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Classe" IS 'Classe de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Ordre" IS 'Ordre de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Famille" IS 'Famille de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Rang_taxo" IS 'Rang taxonomique de l''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Nombre_min" IS 'Nombre minimal d''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Nombre_max" IS 'Nombre maximal d''objet dénombré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Altitude_min" IS 'Altitude minimale';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Altitude_max" IS 'Altitude maximale';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Observateurs" IS 'Personne(s) ayant procédé à l''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Determinateur" IS 'Personne ayant procédé à la détermination';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Validateur" IS 'Personne ayant procédé à la validation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Numero_preuve" IS 'Numéro de l''échantillon de la preuve';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Preuve_numerique" IS 'Adresse web à laquelle on pourra trouver la preuve numérique ou l''archive contenant toutes les preuves numériques (image(s), sonogramme(s), film(s), séquence(s) génétique(s)...)';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Preuve_non_numerique" IS 'Indique si une preuve existe ou non. Par preuve on entend un objet physique ou numérique permettant de démontrer l''existence de l''occurrence et/ou d''en vérifier l''exactitude';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."geom" IS 'Géometrie de la localisation de l''objet observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Comment_releve" IS 'Description libre du contexte de l''observation, aussi succincte et précise que possible';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Comment_occurrence" IS 'Description libre de l''observation, aussi succincte et précise que possible';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Date_creation" IS 'Date de création de la donnée';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Date_modification" IS 'Date de la dernière modification de la données';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Derniere_action" IS 'Date de la dernière action sur l''objet observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."JDD_UUID" IS 'Identifiant unique du jeu de données';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."JDD_nom" IS 'Nom du jeu de données';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."JDD_acteurs" IS 'Acteurs du jeu de données';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."CA_UUID" IS 'Identifiant unique du cadre d''acquisition';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."CA_nom" IS 'Nom du cadre d''acquisition';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."WKT_4326" IS 'Géométrie complète de la localisation en projection WGS 84 (4326)';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."X_centroid_4326" IS 'Latitude du centroïde de la localisation en projection WGS 84 (4326)';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Y_centroid_4326" IS 'Longitude du centroïde de la localisation en projection WGS 84 (4326)';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Nature_objet_geo" IS 'Classe associée au concept de localisation géographique';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Methode_regroupement" IS 'Description de la méthode ayant présidé au regroupement, de façon aussi succincte que possible : champ libre';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Methode_obs" IS 'Méthode d''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Technique_obs" IS 'Indique de quelle manière on a pu constater la présence d''un sujet d''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Statut_biologique" IS 'Comportement général de l''individu sur le site d''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Etat_biologique" IS 'Code de l''état biologique de l''organisme au moment de l''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Naturalite" IS 'Naturalité de l''occurrence, conséquence de l''influence anthropique directe qui la caractérise';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Preuve_existante" IS 'Indique si une preuve existe ou non';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Precision_diffusion" IS 'Niveau maximal de précision de la diffusion souhaitée par le producteur vers le grand public';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Stade_vie" IS 'Stade de développement du sujet de l''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Sexe" IS 'Sexe du sujet de l''observation';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Objet_denombrement" IS 'Objet sur lequel porte le dénombrement';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Type_denombrement" IS 'Méthode utilisée pour le dénombrement (INSPIRE)';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Niveau_sensibilite" IS 'Indique si l''observation ou le regroupement est sensible d''après les principes du SINP et à quel degré';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Statut_observation" IS 'Indique si le taxon a été observé directement/indirectement (indices de présence), ou bien non observé';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Floutage_DEE" IS 'Indique si un floutage a été effectué avant (par le producteur) ou lors de la transformation en DEE';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Statut_source" IS 'Indique si la DS de l’observation provient directement du terrain (via un document informatisé ou une base de données), d''une collection, de la littérature, ou n''est pas connu';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Type_info_geo" IS 'Type d''information géographique';
COMMENT ON COLUMN gn_exports.v_synthese_sinp."Methode_determination" IS 'Description de la méthode utilisée pour déterminer le taxon lors de l''observation';

-- Ajout d'un export par défaut basé sur la vue gn_exports.v_synthese_sinp
INSERT INTO gn_exports.t_exports (label, schema_name, view_name, "desc", geometry_field, geometry_srid, public, id_licence)
VALUES ('Synthese SINP', 'gn_exports', 'v_synthese_sinp', 'Export des données de la synthèse au standard SINP', 'geom', 4326, TRUE, 1);


----------------------
-- Prepare Export RDF
----------------------

-- Vue spécifique pour l'export SINP sémantique au format RDF
--DROP VIEW gn_exports.v_exports_synthese_sinp_rdf;

CREATE OR REPLACE VIEW gn_exports.v_exports_synthese_sinp_rdf AS
    WITH deco AS (
         SELECT s_1.id_synthese,
            n1.label_default AS "ObjGeoTyp",
            n2.label_default AS "methGrp",
            n3.label_default AS "obsMeth",
            n4.label_default AS "obsTech",
            n5.label_default AS "ocEtatBio",
            n6.label_default AS "ocStatBio",
            n7.label_default AS "ocNat",
            n8.label_default AS "preuveOui",
            n9.label_default AS "difNivPrec",
            n10.label_default AS "ocStade",
            n11.label_default AS "ocSex",
            n12.label_default AS "objDenbr",
            n13.label_default AS "denbrTyp",
            n14.label_default AS "sensiNiv",
            n15.label_default AS "statObs",
            n16.label_default AS "dEEFlou",
            n17.label_default AS "statSource",
            n18.label_default AS "typInfGeo",
            n19.label_default AS "ocMethDet"
           FROM gn_synthese.synthese s_1
             LEFT JOIN ref_nomenclatures.t_nomenclatures n1 ON s_1.id_nomenclature_geo_object_nature = n1.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n2 ON s_1.id_nomenclature_grp_typ = n2.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n3 ON s_1.id_nomenclature_obs_meth = n3.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n4 ON s_1.id_nomenclature_obs_technique = n4.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n5 ON s_1.id_nomenclature_bio_status = n5.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n6 ON s_1.id_nomenclature_bio_condition = n6.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n7 ON s_1.id_nomenclature_naturalness = n7.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n8 ON s_1.id_nomenclature_exist_proof = n8.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n9 ON s_1.id_nomenclature_diffusion_level = n9.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n10 ON s_1.id_nomenclature_life_stage = n10.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n11 ON s_1.id_nomenclature_sex = n11.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n12 ON s_1.id_nomenclature_obj_count = n12.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n13 ON s_1.id_nomenclature_type_count = n13.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n14 ON s_1.id_nomenclature_sensitivity = n14.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n15 ON s_1.id_nomenclature_observation_status = n15.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n16 ON s_1.id_nomenclature_blurring = n16.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n17 ON s_1.id_nomenclature_source_status = n17.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n18 ON s_1.id_nomenclature_info_geo_type = n18.id_nomenclature
             LEFT JOIN ref_nomenclatures.t_nomenclatures n19 ON s_1.id_nomenclature_determination_method = n19.id_nomenclature
),
        info_dataset AS (
        SELECT da.id_dataset, r.label_default, org.uuid_organisme, nom_organisme
        FROM gn_meta.cor_dataset_actor da
        JOIN ref_nomenclatures.t_nomenclatures r
        ON da.id_nomenclature_actor_role = r.id_nomenclature
        JOIN utilisateurs.bib_organismes org
        ON da.id_organism = org.id_organisme
        WHERE r.mnemonique = 'Producteur du jeu de données'
)
 SELECT s.id_synthese AS "idSynthese",
    s.unique_id_sinp AS "permId",
    COALESCE(s.unique_id_sinp_grp, s.unique_id_sinp) AS "permIdGrp",
    s.count_min AS "denbrMin",
    s.count_max AS "denbrMax",
    s.meta_v_taxref AS "vTAXREF",
    s.sample_number_proof AS "sampleNumb",
    s.digital_proof AS "preuvNum",
    s.non_digital_proof AS "preuvNoNum",
    s.altitude_min AS "altMin",
    s.altitude_max AS "altMax",
    public.st_astext(s.the_geom_4326) AS "geom",
    s.date_min AS "dateDebut",
    s.date_max AS "dateFin",
    s.validator AS "validateur",
    s.observers AS "observer",
    s.id_digitiser,
    s.determiner AS "determiner",
    s.comment_context AS "obsCtx",
    s.comment_description AS "obsDescr",
    s.meta_create_date,
    s.meta_update_date,
    d.unique_dataset_id AS "jddId",
    d.dataset_name AS "jddCode",
    d.id_acquisition_framework,
    t.cd_nom AS "cdNom",
    t.cd_ref AS "cdRef",
    s.nom_cite AS "nomCite",
    t.nom_complet AS nom_complet,
    public.st_x(public.st_transform(s.the_geom_point, 4326)) AS "x_centroid",
    public.st_y(public.st_transform(s.the_geom_point, 4326)) AS "y_centroid",
    COALESCE(s.meta_update_date, s.meta_create_date) AS lastact,
    deco."ObjGeoTyp",
    deco."methGrp",
    deco."obsMeth",
    deco."obsTech",
    deco."ocEtatBio",
    deco."ocNat",
    deco."preuveOui",
    deco."difNivPrec",
    deco."ocStade",
    deco."ocSex",
    deco."objDenbr",
    deco."denbrTyp",
    deco."sensiNiv",
    deco."statObs",
    deco."dEEFlou",
    deco."statSource",
    deco."typInfGeo",
    info_d.uuid_organisme as "ownerInstitutionID",
    info_d.nom_organisme as "ownerInstitutionCode"
FROM gn_synthese.synthese s
JOIN taxonomie.taxref t ON t.cd_nom = s.cd_nom
JOIN gn_meta.t_datasets d ON d.id_dataset = s.id_dataset
JOIN gn_synthese.t_sources sources ON sources.id_source = s.id_source
JOIN deco ON deco.id_synthese = s.id_synthese
LEFT OUTER JOIN info_dataset info_d ON info_d.id_dataset = d.id_dataset;
