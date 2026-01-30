SET search_path TO erp;

-- un salaire ne peut pas diminuer sans justification

CREATE OR REPLACE FUNCTION trg_check_and_log_salary()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.salary < OLD.salary THEN
        RAISE EXCEPTION 'Règle RH : Le salaire ne peut pas être diminué (Ancien: %, Nouveau: %)', OLD.salary, NEW.salary;
    END IF;

    IF NEW.salary <> OLD.salary THEN
        INSERT INTO salary_history (emp_id, old_salary, new_salary, changed_by)
        VALUES (OLD.emp_id, OLD.salary, NEW.salary, CURRENT_USER);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_salary_update ON employee;
CREATE TRIGGER trg_salary_update
    BEFORE UPDATE OF salary ON employee
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_and_log_salary();


-- une facture validée devient immuable


CREATE OR REPLACE FUNCTION trg_freeze_invoice_header()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IN ('VALIDATED', 'PAID') THEN
        IF NEW.status = 'PAID' AND OLD.status = 'VALIDATED' THEN
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'Document verrouillé : Impossible de modifier une facture validée.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoice_lock ON invoice;
CREATE TRIGGER trg_invoice_lock
    BEFORE UPDATE OR DELETE ON invoice
    FOR EACH ROW
    EXECUTE FUNCTION trg_freeze_invoice_header();

CREATE OR REPLACE FUNCTION trg_freeze_invoice_lines()
RETURNS TRIGGER AS $$
DECLARE parent_status invoice_status;
target_inv_id INT;
BEGIN
    target_inv_id := COALESCE(NEW.inv_id, OLD.inv_id);
    SELECT status INTO parent_status FROM invoice WHERE inv_id = target_inv_id;

    IF parent_status IN ('VALIDATED', 'PAID') THEN
        RAISE EXCEPTION 'Intégrité : Impossible de modifier les lignes dune facture validée.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoice_line_lock ON invoice_line;
CREATE TRIGGER trg_invoice_line_lock
BEFORE INSERT OR UPDATE OR DELETE ON invoice_line
FOR EACH ROW
EXECUTE FUNCTION trg_freeze_invoice_lines();


-- une facture doit avoir au moins une ligne


CREATE OR REPLACE FUNCTION trg_check_invoice_completeness()
RETURNS TRIGGER AS $$
DECLARE
line_count INT;
BEGIN
    IF NEW.status = 'VALIDATED' AND OLD.status = 'DRAFT' THEN
        SELECT COUNT(*) INTO line_count FROM invoice_line WHERE inv_id = NEW.inv_id;

        IF line_count = 0 THEN
            RAISE EXCEPTION 'Processus de Validation : La facture doit contenir au moins une ligne.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoice_validation ON invoice;
CREATE TRIGGER trg_invoice_validation
BEFORE UPDATE OF status ON invoice
FOR EACH ROW
EXECUTE FUNCTION trg_check_invoice_completeness();


-- un employé ne peut pas être affecté deux fois au même projet
-- J'avais deja mis en place cette restriction à la création de la table avec les clefs primaires, mais voici le script qui aurait correspondu

CREATE OR REPLACE FUNCTION trg_prevent_duplicate_project_assignment()
RETURNS TRIGGER AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM erp.employee_project
        WHERE emp_id = NEW.emp_id
          AND proj_id = NEW.proj_id
    ) THEN
        RAISE EXCEPTION 'Doublon détecté : L''employé % est déjà affecté au projet %.', NEW.emp_id, NEW.proj_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_assignment ON erp.employee_project;
CREATE TRIGGER trg_check_assignment
BEFORE INSERT ON erp.employee_project
FOR EACH ROW
EXECUTE FUNCTION trg_prevent_duplicate_project_assignment();