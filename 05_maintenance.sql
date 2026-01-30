\c db_erp
SET search_path TO erp, public;

-- AUDIT


CREATE TABLE IF NOT EXISTS audit_log (

    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    operation VARCHAR(10),
    record_id TEXT,
    old_values JSONB,
    new_values JSONB,
    performed_by VARCHAR(50),
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

CREATE INDEX idx_audit_json ON audit_log USING GIN (old_values);

CREATE OR REPLACE FUNCTION trg_audit_generic()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_values, performed_by)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.emp_id::TEXT, row_to_json(OLD), CURRENT_USER);
RETURN OLD;
ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, performed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.emp_id::TEXT, row_to_json(OLD), row_to_json(NEW), CURRENT_USER);
RETURN NEW;
END IF;
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_employee ON employee;
CREATE TRIGGER trg_audit_employee
    AFTER UPDATE OR DELETE ON employee
    FOR EACH ROW
    EXECUTE FUNCTION trg_audit_generic();


-- LISTEN / NOTIFY
--Si un salaire augmente de plus de 50%, la base envoie une notification instantanée au backend (Asynchrone).

CREATE OR REPLACE FUNCTION trg_detect_suspicious_salary()
RETURNS TRIGGER AS $$
DECLARE
v_percent_change NUMERIC;
BEGIN
    v_percent_change := (NEW.salary - OLD.salary) / OLD.salary * 100;

    IF v_percent_change > 50 THEN
        -- Envoi du signal 'salary_alert' avec un message JSON
        PERFORM pg_notify('salary_alert', json_build_object(
            'emp_id', NEW.emp_id,
            'old_salary', OLD.salary,
            'new_salary', NEW.salary,
            'user', CURRENT_USER
        )::text);

        RAISE NOTICE 'ALERTE : Augmentation suspecte détectée ! Notification envoyée.';
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_alert_salary ON employee;
CREATE TRIGGER trg_alert_salary
    AFTER UPDATE OF salary ON employee
    FOR EACH ROW
    EXECUTE FUNCTION trg_detect_suspicious_salary();


-- vues matérialisées
--  stocke physiquement le résultat.

DROP MATERIALIZED VIEW IF EXISTS mv_payroll_dashboard;
CREATE MATERIALIZED VIEW mv_payroll_dashboard AS
SELECT
    d.name AS department,
    COUNT(e.emp_id) AS staff_count,
    SUM(e.salary) AS total_payroll,
    ROUND(AVG(e.salary), 2) AS avg_salary
FROM department d
         LEFT JOIN employee e ON d.dept_id = e.dept_id
GROUP BY d.name
    WITH DATA;

CREATE UNIQUE INDEX idx_mv_dept ON mv_payroll_dashboard(department);


-- MAINTENANCE & PURGE


CREATE OR REPLACE PROCEDURE sp_maintenance_routine()
LANGUAGE plpgsql
AS $$
DECLARE
v_deleted_count INT;
BEGIN
DELETE FROM audit_log WHERE performed_at < NOW() - INTERVAL '1 year';
GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

RAISE NOTICE 'Maintenance : % lignes archivées supprimées.', v_deleted_count;

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_payroll_dashboard;
    RAISE NOTICE 'Maintenance : Tableau de bord RH mis à jour.';

    ANALYZE erp.audit_log;
END;
$$;


-- EVENT TRIGGER
-- Empêche la suppression de tables (DROP TABLE) par accident.


CREATE OR REPLACE FUNCTION trg_prevent_drop_table()
RETURNS EVENT_TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'INTERDIT : La suppression de table est désactivée en production via Event Trigger.';
END;
$$ LANGUAGE plpgsql;

-- trigger uniquement pour l'exemple (à commenter si besoin de supprimer)
DROP EVENT TRIGGER IF EXISTS evt_no_drop;
CREATE EVENT TRIGGER evt_no_drop
    ON sql_drop
    EXECUTE FUNCTION trg_prevent_drop_table();