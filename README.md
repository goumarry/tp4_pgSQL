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