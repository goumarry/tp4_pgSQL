# TP4 - Gestion des Deadlocks (PostgreSQL)

### 1. Analyse du problème (Deadlock)
Lors de l'exécution simultanée, on observe un **blocage mutuel** entre les deux transactions :
* **Transaction 1 (Alice vers Bob) :** Elle a verrouillé le compte d'Alice et attend que le compte de Bob se libère.
* **Transaction 2 (Bob vers Alice) :** Elle a verrouillé le compte de Bob et attend que le compte d'Alice se libère.

C'est ce qu'on appelle une **attente circulaire** : T1 attend T2, et T2 attend T1. Comme personne ne veut lâcher son verrou, tout est bloqué indéfiniment.

### 2. Réaction de PostgreSQL
Heureusement, le SGBD détecte ce blocage infini.
* Pour résoudre le problème, il décide arbitrairement d'annuler (**ROLLBACK**) une des deux transactions (la "victime").
* Cela permet à l'autre transaction de terminer son exécution normalement.
* C'est pour cette raison que seul le virement d'Alice a fonctionné dans notre test, tandis que celui de Bob a échoué avec une erreur `deadlock detected`.

### 3. Ma solution
Pour empêcher ce problème sans désactiver la concurrence, j'ai mis en place une règle simple : **l'Ordre de Verrouillage Global**.

**Le principe :**
Peu importe qui envoie de l'argent à qui, on verrouille toujours les comptes dans le même ordre (du plus petit ID au plus grand).

**Code ajouté :**
En début de transaction, je force cet ordre de verrouillage :
`SELECT ... FROM Comptes ... ORDER BY id_compte ASC FOR UPDATE;`

**Résultat :**
Les transactions ne se croisent plus. Si la Transaction 1 commence, la Transaction 2 attend sagement son tour (file d'attente) au lieu de créer un blocage. Il n'y a plus d'erreur.


# TP 6 - PostgreSQL Avancé
## PARTIE 4 – Transactions, Concurrence & Deadlocks

### 1. Le Problème : L'Interblocage (Deadlock)
Un deadlock est une situation critique où deux transactions se bloquent mutuellement. Cela arrive quand l'Utilisateur A verrouille une ressource X et attend la Y, alors que l'Utilisateur B a verrouillé la Y et attend la X. PostgreSQL détecte ce cercle vicieux et force l'arrêt d'une des deux transactions.

### 2. Scénario de reproduction (Échec)
Deadlock avec deux terminaux :

```sql
-- Terminal 1 : Verrouille G, attend, puis veut H
BEGIN;
UPDATE erp.invoice SET status = 'VALIDATED' WHERE customer_name = 'Client G';
SELECT pg_sleep(5);
UPDATE erp.invoice SET status = 'VALIDATED' WHERE customer_name = 'Client H'; -- CRASH

-- Terminal 2 : Verrouille H, puis veut G
BEGIN;
UPDATE erp.invoice SET status = 'VALIDATED' WHERE customer_name = 'Client H';
UPDATE erp.invoice SET status = 'VALIDATED' WHERE customer_name = 'Client G'; -- BLOCAGE
```


### 3. La Solution Technique
J'ai implémenté une procédure stockée (sp_validate_invoices_batch) dans le script 04_transactions.sql qui utilise l'instruction spécifique : SELECT ... FOR UPDATE SKIP LOCKED

### 4. Pourquoi cela résout le problème ?
L'approche classique mettait les transactions en file d'attente sur les ressources verrouillées, créant le bouchon. L'instruction SKIP LOCKED change ce comportement : elle demande à la base de données d'ignorer immédiatement les lignes déjà verrouillées par d'autres et de passer aux suivantes. Cela supprime l'attente et permet aux administrateurs de traiter les factures en parallèle sans jamais entrer en conflit.

# RENDU FINAL TP 6
# ERP PostgreSQL - Documentation Technique

## 1. Contexte
Ce projet implémente le backend d'un ERP (Enterprise Resource Planning) en utilisant exclusivement les fonctionnalités natives de PostgreSQL. L'objectif est de garantir l'intégrité des données, la sécurité et la performance directement au niveau de la base de données (approche "Database Centric").

## 2. Architecture & Choix Techniques

### A. Sécurité (Role-Based Access Control)
J'ai appliqué le principe du **Moindre Privilège** :
* **`erp_admin`** : Super-utilisateur du schéma.
* **`erp_hr`** : Accès aux données sensibles (salaires) et écriture sur les employés.
* **`erp_app`** : Compte de service pour le backend. Accès écriture facturation/projets. Accès lecture seule aux employés via une **Vue Sécurisée** (`vw_employee_public`) qui masque la colonne salaire.
* **`erp_readonly`** : Accès auditeur, restreint aux vues publiques.

### B. Règles Métier & Intégrité
Plutôt que de gérer la logique dans le code applicatif (PHP/Java), nous utilisons des **Triggers** :
* **Immutabilité** : Une fois une facture passée en statut `VALIDATED`, un trigger bloque toute modification ou suppression (`trg_freeze_invoice`).
* **Audit** : Historisation automatique des changements de salaire dans `salary_history`.

### C. Gestion de la Concurrence (Deadlocks)
Problème identifié : Lors de la validation en masse de factures, des interblocages (Deadlocks) surviennent si deux transactions traitent les mêmes factures dans un ordre inversé.
**Solution** : Utilisation de `FOR UPDATE SKIP LOCKED`.
Cela permet aux transactions de sauter les lignes déjà verrouillées par un autre processus et de traiter les suivantes, assurant une parallélisation totale sans blocage.

### D. Maintenance & Forensic
* **Audit JSON** : Utilisation du type `JSONB` pour stocker les anciennes et nouvelles valeurs dans `audit_log`. Cela offre une flexibilité totale si le schéma des tables change.
* **Performance** : Mise en place d'une **Vue Matérialisée** (`mv_payroll_dashboard`) pour les statistiques RH lourdes, afin d'éviter de recalculer les agrégats à chaque consultation.
* **Protection Structurelle** : Un **Event Trigger** empêche la suppression accidentelle de tables (`DROP TABLE`) en production.
* **Monitoring** : Système `LISTEN / NOTIFY` pour alerter le backend en temps réel en cas de variation suspecte de salaire (>50%).

## 3. Structure du projet
* `01_schema.sql` : Création des tables et contraintes.
* `02_business_rules.sql` : Fonctions PL/pgSQL et Triggers métier.
* `03_security.sql` : Gestion des rôles et droits (GRANT/REVOKE).
* `04_transactions.sql` : Procédure de traitement par lots avec gestion de concurrence.
* `05_maintenance.sql` : Outils d'audit, vues matérialisées et maintenance.

## 4. Installation
```bash
psql -d db_erp -f 01_schema.sql
psql -d db_erp -f 02_business_rules.sql
sudo -u postgres psql -d db_erp -f 03_security.sql
psql -d db_erp -f 04_transactions.sql
sudo -u postgres psql -d db_erp -f 05_maintenance.sql

### 2. Le Diagramme Relationnel (ERD)

Pour le schéma, je te fournis le code **Mermaid.js**. C'est le standard actuel pour les docs techniques.
Tu peux coller ce code sur [Mermaid Live Editor](https://mermaid.live/) pour générer l'image, ou le mettre directement dans ton Markdown si ton éditeur le supporte.

```mermaid
erDiagram
    DEPARTMENT ||--|{ EMPLOYEE : "has"
    EMPLOYEE ||--o{ PROJECT : "manages"
    EMPLOYEE ||--o{ INVOICE : "creates"
    EMPLOYEE ||--|{ SALARY_HISTORY : "has history"
    EMPLOYEE }|--|{ PROJECT : "works on (employee_project)"
    INVOICE ||--|{ INVOICE_LINE : "contains"
    
    DEPARTMENT {
        int dept_id PK
        string name
        numeric budget
    }

    EMPLOYEE {
        int emp_id PK
        string email
        numeric salary "Confidential"
        string role
        int dept_id FK
    }

    PROJECT {
        int proj_id PK
        string name
        date end_date
    }

    INVOICE {
        int inv_id PK
        string status "DRAFT/VALIDATED"
        numeric total_amount
        int emp_id FK
    }

    AUDIT_LOG {
        int log_id PK
        string table_name
        jsonb old_values
        jsonb new_values
    }