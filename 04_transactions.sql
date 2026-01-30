SET search_path TO erp;


CREATE OR REPLACE PROCEDURE sp_validate_invoices_batch(p_admin_name VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
r_inv RECORD;
    v_count INT := 0;
BEGIN
    RAISE NOTICE '--- Démarrage du traitement par % ---', p_admin_name;


FOR r_inv IN
SELECT inv_id, customer_name
FROM invoice
WHERE status = 'DRAFT'
ORDER BY inv_id ASC
    FOR UPDATE SKIP LOCKED
    LOOP
        PERFORM pg_sleep(2);

UPDATE invoice
SET status = 'VALIDATED',
    validated_at = CURRENT_TIMESTAMP
WHERE inv_id = r_inv.inv_id;

v_count := v_count + 1;
        RAISE NOTICE 'Facture % (%) validée.', r_inv.inv_id, r_inv.customer_name;

COMMIT;
END LOOP;

    RAISE NOTICE '--- Fin du traitement. % factures traitées par % ---', v_count, p_admin_name;
END;
$$;