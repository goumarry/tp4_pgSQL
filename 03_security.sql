\c db_erp
SET search_path TO erp, public;

-- pour relancer le script

DROP ROLE IF EXISTS erp_admin;
DROP ROLE IF EXISTS erp_hr;
DROP ROLE IF EXISTS erp_app;
DROP ROLE IF EXISTS erp_readonly;

--roles

CREATE ROLE erp_admin WITH LOGIN PASSWORD 'admin123';

CREATE ROLE erp_hr WITH LOGIN PASSWORD 'hr123';

CREATE ROLE erp_app WITH LOGIN PASSWORD 'app123';

CREATE ROLE erp_readonly WITH LOGIN PASSWORD 'read123';


-- vue sécurisée

CREATE OR REPLACE VIEW vw_employee_public AS
SELECT
    emp_id,
    first_name,
    last_name,
    email,
    dept_id,
    role,
    is_active
FROM erp.employee;

ALTER VIEW vw_employee_public OWNER TO postgres;


-- privilèges


REVOKE ALL ON SCHEMA erp FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA erp FROM PUBLIC;

-- Droit d'entrée dans le schéma (USAGE) pour nos 4 rôles
GRANT USAGE ON SCHEMA erp TO erp_admin, erp_hr, erp_app, erp_readonly;

-- admin
-- Il a tous les droits sur toutes les tables et séquences
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA erp TO erp_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA erp TO erp_admin;


-- rh
-- Lecture seule sur les données structurelles (Départements, Projets)
GRANT SELECT ON department, project TO erp_hr;
-- Plein pouvoir sur les employés et l'historique salaire
GRANT ALL ON employee, salary_history, employee_project TO erp_hr;
-- Droit d'utiliser les compteurs (séquences) pour créer des employés
GRANT USAGE, SELECT ON SEQUENCE employee_emp_id_seq, salary_history_hist_id_seq TO erp_hr;


-- app
-- L'appli gère les factures et projets : Lecture/Ecriture
GRANT ALL ON invoice, invoice_line, project, employee_project TO erp_app;
GRANT USAGE, SELECT ON SEQUENCE invoice_inv_id_seq, invoice_line_line_id_seq, project_proj_id_seq TO erp_app;

-- L'appli doit pouvoir lire les employés (pour les menus déroulants)
GRANT SELECT ON vw_employee_public TO erp_app;


-- read only
-- Lecture seule sur les objets non sensibles
GRANT SELECT ON department, project, invoice, invoice_line TO erp_readonly;
-- Lecture seule sur les employés VIA LA VUE (Sécurité)
GRANT SELECT ON vw_employee_public TO erp_readonly;

-- security definer

CREATE OR REPLACE FUNCTION sp_add_audit_log(p_operation VARCHAR, p_table VARCHAR)
RETURNS VOID AS $$
BEGIN
INSERT INTO erp.audit_log (operation, table_name, performed_by)
VALUES (p_operation, p_table, SESSION_USER);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- SECURITY DEFINER = La fonction s'exécute avec les droits du CRÉATEUR (postgres),
-- pas ceux de l'exécuteur.

GRANT EXECUTE ON FUNCTION sp_add_audit_log TO erp_app;