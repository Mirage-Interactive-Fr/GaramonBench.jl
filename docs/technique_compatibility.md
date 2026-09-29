# Garamon — techniques seules et combinaisons à éprouver

Version du 27 septembre 2026. Cette étude intègre les **quinze pistes du copier-coller** et les techniques de la roadmap existante. Elle définit 46 familles, soit **1 035 paires distinctes**. Elle ne présente aucun nouveau temps de calcul : la compatibilité ci-dessous est une analyse de contrats et de mathématiques, à confirmer par les expériences indiquées. Une composition possible peut perdre en temps, en mémoire ou en stabilité.

La matrice porte sur **deux techniques appliquées au même sous-calcul**, ou sur leur composition explicite avec conversion. Deux méthodes concurrentes restent utilisables dans deux branches différentes du même programme. Une compatibilité par paires ne prouve jamais qu'un assemblage de trois méthodes est valide : l'ordre des transformations, les certificats et le budget cumulé doivent encore être vérifiés.

## Lire les cases sans leur faire dire trop

| Case | Sens | Admission expérimentale |
|---|---|---|
| **O** | Compatible par construction dans le domaine commun décrit dans l'inventaire. | Tester néanmoins l'intégration et mesurer le coût total ; ce symbole ne promet ni API existante ni gain. |
| **C1…C20** | Compatible **sous la condition précisément décrite** dans la table des conditions. | La condition doit être vérifiée avant le calcul et invalider le plan si elle cesse d'être vraie. |
| **X1** | Deux politiques alternatives de remplacement du **même cache**, au même niveau. | Comparaison solo ; une hiérarchie de caches serait une nouvelle méthode, avec espaces et budgets distincts. |
| **?** | Composition utile ou contrat de transfert **non démontré** dans cet audit. | Expérience de faisabilité mathématique et de conversion avant tout benchmark. Ce n'est pas un verdict négatif. |
| **—** | Même famille. | Les variantes internes doivent aussi être comparées ; elles sont précisées dans l'inventaire. |

La suppression heuristique irréversible de contributions est **incompatible avec une demande de produit exact**, quel que soit l'autre composant. Cela vaut aussi pour une roulette de contributions. La roulette d'éviction de plans n'a pas cette incompatibilité. Un calcul différé peut rendre un résultat exact seulement après reconstruction certifiée de tout ce qui est nécessaire ; le simple fait que l'expression soit récursive ne constitue pas cette reconstruction.

## Inventaire, contrats et réalité du code

« Présent » signifie chemin repéré dans les sources, avec les limites des rapports existants. « Prototype » ne signifie pas voie publique complète. « Recherche » signifie que l'essai reste à implémenter. Les tests indiqués plus bas doivent être conservés même si leur premier résultat est défavorable.

| ID | Technique et variantes à comparer | Domaine / contrat | État et ancrage |
|---|---|---|---|
| 01 | Dense global | Tous coefficients ; coût au moins proportionnel à la sortie matérialisée | Présent : `src/multivectors.jl`, `products.jl` |
| 02 | Supports creux : dictionnaire, liste triée | Support réel ; inclure tri/index et mises à jour | Présent : `multivectors.jl`, `gradeblocks.jl` ; liste publique spécialisée UInt64 |
| 03 | Blocs de grades, homogènes | Grades fixes, occupation variable ; borner les binomiaux | Présent : `plans.jl`, `gradeblocks.jl` |
| 04 | Récursion ciblée / arbre virtuel | Propager la demande jusqu'aux contributions admissibles | Présent : `dsl.jl` ; analogue C++ à distinguer du stockage |
| 05 | Filtrage exact de grades dans la récursion | Grades de l'algèbre ambiante, règles de contraction correctes | Présent dans les expériences récursives et DSL |
| 06 | Jointure XOR à deux facteurs | Base diagonale pour GP ; wedge a ses propres règles | Présent : `products.jl` ; quelques sorties |
| 07 | Jointure à trois facteurs, join3 | Trois facteurs et sorties ciblées, ordre de produit conservé | Présent : `triplejoin.jl`, `products.jl` |
| 08 | Plans préparés : support exact, grade entier, TripleJoinPlan | Structure stable ; coefficients relus ; budgets de chemins | Présent : `plans.jl`, `triplejoin.jl` |
| 09 | Workspaces préalloués | Buffers possédés par l'appel ; un workspace par calcul concurrent | Présent : `workspace.jl`, `triplejoin.jl` ; limite d'admission, pas plafond RSS/JIT |
| 10 | Cache LRU | Structures indexées par algèbre, opération et supports | Présent : `cache.jl` ; pas de cache de coefficients |
| 11 | Roulette d'éviction de plans | Même exactitude que sans cache ; aléa sur rétention | Présent : `cache.jl`, politique `:roulette` |
| 12 | TinyLFU, admission par fréquence | Ajouter une admission au cache, éventuellement LRU/SIEVE dessous | Recherche ; comparer aussi coût des compteurs |
| 13 | SIEVE | Politique de remplacement de plans, adaptation à démontrer | Recherche ; aucune vitesse GA déduite des caches web |
| 14 | Génération / spécialisation à la volée | Programme borné ; distinguer compilation et exécution | Présent : `generated.jl`, plafond de chemins |
| 15 | Catalogue natif / précompilation / cache du compilateur | Identités de type et code compatibles ; version/cible enregistrées | Expériences de cycle de vie dans `perf/precompile_lifecycle*` |
| 16 | DAG, partage et mémoïsation pendant l'évaluation | Sous-expressions pures ; invalidation entre coefficients modifiés | Présent : `dsl.jl` ; cache de valeurs inter-appels distinct et non livré |
| 17 | Blades factorisés, versors, chaînes de réflexions | Préserver décomposabilité ou factorisation et ordre | Présent : `transformations.jl` ; pas de somme générale compacte garantie |
| 18 | Sous-espace actif | Réduction aux directions coordonnées ; généralisation linéaire à certifier | Présent : `subspace.jl`, `CoordinateSubspace` ; sous-espace linéaire général en recherche |
| 19 | TT/MPS exact, automate de parité | Diagonale, rang et cœurs bornés ; aucune troncature | Prototype : `trains.jl`, `max_rank`, `max_entries` |
| 20 | ZDD / DAG de supports pondéré | Partager sous-graphes et coefficients, signe compris | Prototype booléen dans `benchmark/compare.jl` ; produit pondéré à établir |
| 21 | Trie matérialisé / préfixes | Index ou parcours stocké ; préparer et mettre à jour les nœuds | Prototype dans `benchmark/compare.jl` |
| 22 | Représentations matricielles / GFFT Clifford | Signature couverte, coefficient fidèle, transformations aller-retour | Recherche dense ; aucune Walsh scalaire naïve |
| 23 | E-graphs, réécriture algébrique / planification | Identités valides pour la métrique et le contrat numérique | Recherche ; à distinguer du DAG déjà présent |
| 24 | Contributions différées et replay exact | Conserver provenance ; réinjecter tout le nécessaire et respecter ordre si bit-identité | Prototype dans `perf/pruning_recurrences*` |
| 25 | Pruning approché, seuil, roulette de contributions, learning | Contrat approché explicite ; erreur sur la trajectoire entière | Prototype séparé des produits exacts ; ne pas confondre avec 11 |
| 26 | Sélection, HPO, learning, attribution SHAP | Classer seulement candidats admissibles ; coût de sélection inclus | Protocole ; `selector.jl` contient un sélecteur expérimental analytique non entraîné |
| 27 | Threads CPU / SIMD / lots compacts | Réduction ordonnée ou tolérance annoncée ; buffers distincts | PackedProductBatch présent ; exploration threads préparée |
| 28 | Processus CPU | Duplication mémoire, compilation par processus et communications incluses | Protocole et smoke dans `perf/parallel_batches*` |
| 29 | GPU | Kernels réellement supportés, mémoire et transferts inclus | Recherche ; présence matérielle ne prouve pas un backend |
| 30 | Masques et indexation : UInt64, UInt128, BigInt, rang combinatoire | Même masque mathématique ; débordements et limites vérifiés | Présent : `algebra.jl`, `indexing.jl` |
| 31 | **Rang binaire des supports** | Sous-espace de F₂ⁿ fermé par XOR ; cocycle/facteurs transportés | Nouvelle recherche ; différent de 18 |
| 32 | **Secteurs invariants, centre et cœur non commutatif** | Opérations préservant le secteur et observation limitée à ce secteur | Nouvelle recherche ; projection explicite |
| 33 | **Radical, degré radical et nilpotence** | Radical de la métrique certifié ; degré radical distinct du grade | Nouvelle recherche ; PGA prioritaire |
| 34 | **Identités de faible degré / polynôme minimal** | Relation exacte vérifiée ; constantes et élément concernés identifiés | Nouvelle recherche ; puissances/inverse/exponentielle |
| 35 | **Pfaffien de contractions** | Partie scalaire d'un produit ordonné de 2m vecteurs | Nouvelle recherche ; sortie multivecteur générale hors contrat |
| 36 | **Rang de Gram croisée / plans principaux** | Deux blades décomposables ; rang certifié ; angles euclidiens spécialisés | Nouvelle recherche ; sous-variantes exactes et numériques distinctes |
| 37 | **Opérateurs fermioniques gaussiens** | Famille fermée et signature couverte ; signe/phase/scalaires conservés | Nouvelle recherche ; action vectorielle seule insuffisante |
| 38 | **Changement de base par petites transformations** | Extension extérieure de rotations Givens et facteurs nécessaires | Nouvelle recherche ; 01/03 comparés à matrices induites et outermorphism actuel |
| 39 | **Convolution disjointe signée rapide** | Wedge dense ; arithmétique/signature et conversions du théorème | Nouvelle recherche ; pas convolution commutative ordinaire |
| 40 | **Synthèse de noyaux bilinéaires** | Identité du tenseur prouvée sur le corps d'exécution | Nouvelle recherche ; additions, code et stabilité mesurés |
| 41 | **Superoptimisation vérifiée** | Petit noyau, ISA précise et sémantique LLVM/FP fixée | Nouvelle recherche hors ligne ; preuve dans le modèle déclaré |
| 42 | **Fronts de travail / wavefront** | Lots d'états récursifs ; compacter/classer sous budget | Nouvelle recherche CPU et GPU ; hybride profondeur/front |
| 43 | **Adaptive Radix Tree / index compact** | Arbre réellement matérialisé servant d'index de supports | Nouvelle recherche ; opposer tableau trié et trie |
| 44 | **Multimodulaire / CRT** | Entiers/rationnels exacts avec reconstruction certifiée | Nouvelle recherche ; runtime Float64 général hors contrat |
| 45 | **Prédicats filtrés / précision adaptative** | Signe ou décision certifiée ; reprise exacte depuis les données sources | Nouvelle recherche ; ne calcule pas tous les coefficients |
| 46 | **Certificats structurels propagés par plans/constructeurs** | Propriété, domaine, dépendances et invalidation vérifiables | Nouvelle couche transversale ; éviter un type par valeur numérique |

Ancrages de source relus pour cette matrice : `ProductWorkspace` (`workspace.jl:14–55`) vérifie le plan et l'admission mémoire ; `train_product` (`trains.jl:79–110`) refuse une métrique non diagonale et borne les cœurs ; `CoordinateSubspace` (`subspace.jl:1–56`) transporte une sous-matrice principale ; `ProductPlanCache` (`cache.jl:2–24`) accepte actuellement seulement LRU/roulette ; `TripleSelectorBudget` et `_TRIPLE_CANDIDATES` (`selector.jl:1–23`) limitent les cinq stratégies du sélecteur expérimental. Ces ancrages sont des observations de code local, pas une preuve que les nouvelles compositions sont déjà implémentées. Les tableaux et les rapports de la roadmap demeurent la source des mesures antérieures.

## Conditions référencées par les cellules

| Code | Condition vérifiable et risque à mesurer | Test |
|---|---|---|
| C1 | Convertir formats/bases explicitement ; même élément et même requête avant/après. La représentation de sortie et sa copie font partie du coût. | T0, T1 |
| C2 | Préparer la structure réellement réutilisée ; clé comprenant métrique, base, supports, sortie, type et certificats pertinents. Revalider après changement. | T2 |
| C3 | Workspace privatif, durée de vie explicite des vues ; RAM cumulée plans + buffers + copies + JIT. L'économie d'allocations n'implique pas une économie de RSS. | T3 |
| C4 | Compiler/cache natif seulement après stabilisation du contrat ; comptabiliser JIT, taille de code, rechargement et incompatibilité de version/ISA. | T4 |
| C5 | Réécriture/partage préservant ordre algébrique, sorties, dépendances et sémantique FP déclarée ; invalider les valeurs mémorisées. | T5 |
| C6 | Supports/grades certifiés et fermeture maintenue. La simple sparsité observée sur un jeu de coefficients ne vaut pas identité structurelle. | T6 |
| C7 | Réduction **binaire** : conserver φ:F₂ᵈ→F₂ⁿ, c(φu,φv), grade ambiant et requêtes. Le produit réduit n'est pas supposé être Cl(d,0). | N1, T1 |
| C8 | Secteur invariant explicitement demandé, projecteur et actions compatibles. Sortie générale exige tous les secteurs nécessaires et la recomposition. | N2 |
| C9 | Radical certifié et filtration préservée ; aucun vecteur seulement isotrope assimilé au radical ; ordre de l'inverse conservé. | N3 |
| C10 | Sortie spécialisée commune : scalaire de chaîne de vecteurs pour Pfaffien ; identité validée pour l'élément pour polynôme minimal ; facteurs certifiés pour Gram/gaussien. | N4–N7 |
| C11 | Définir la représentation d'interface et mesurer expansion, rang/largeur, repli et sorties ; pas de conversion gratuite présumée. | T1, T6 |
| C12 | Mode approché explicite ; budget d'erreur global mesuré. Une sortie exacte exige reprise depuis données non altérées ou certificat déterministe suffisant. | T7 |
| C13 | Threads/processus/GPU réellement capables d'exécuter le noyau et ses types ; partition sans races, coût synchronisation/transfert et ordre de réduction déclarés. | T8 |
| C14 | Multimodulaire : dénominateurs, mauvais premiers, bornes CRT et reconstruction gérés. Un test nul modulo quelques premiers n'est pas un certificat de zéro. | N14 |
| C15 | Filtre de signe certifié couvrant toutes les erreurs précédentes ; résultat ambigu déclenche reprise exacte. Sous-flux, NaN et cas proches de zéro testés. | N15 |
| C16 | Synthèse/superoptimisation appliquée à un sous-noyau à contrat fixe ; preuve d'équivalence dans le corps et modèle machine ciblés avant mesure. | N10, N11 |
| C17 | Fronts construits à partir de travail réellement évitable ou regroupable ; files bornées, fragmentation/compactage mesurés, profondeur locale de repli. | N12 |
| C18 | Index matérialisé justifié par recherches/réutilisation ; orientation/signes inchangés ; construction, maintenance et mémoire comptées. | N13 |
| C19 | Sélecteur sous gardes exactes ; inclure extraction, choix, conversions et préparation ; apprentissage/test séparés par familles. | T9 |
| C20 | Certificat composable après la transformation ; dépendances suivies ; perte de propriété provoque revalidation ou repli exact explicite. | T6, T10 |

Les codes ciblent le risque dominant de chaque paire ; **toutes** les conditions propres aux deux techniques restent cumulatives. Par exemple une cellule C13 n'annule pas l'obligation C7 du rang binaire ou C8 d'un secteur.

## Matrice complète

La même matrice symétrique est découpée en blocs de colonnes pour rester lisible. Les ID sont définis dans l'inventaire. Les cases `?` sont volontairement conservées : il faudra soit construire un transfert, soit documenter pourquoi aucun sous-calcul commun utile n'a été trouvé.

### Colonnes 01–10

| Ligne / colonne | 01 Dense | 02 Creux/tri | 03 Grades | 04 Récursion | 05 Filtre grades | 06 XOR | 07 Join3 | 08 Plans | 09 Workspace | 10 LRU |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 Dense | — | C1 | C1 | C1 | C1 | C1 | C1 | C2 | C3 | C2 |
| 02 Creux/tri | C1 | — | C1 | C1 | C1 | C1 | C1 | C2 | C3 | C2 |
| 03 Grades | C1 | C1 | — | C1 | C1 | C1 | C1 | O | C3 | C2 |
| 04 Récursion | C1 | C1 | C1 | — | O | C1 | C1 | C2 | C3 | C2 |
| 05 Filtre grades | C1 | C1 | C1 | O | — | O | O | C2 | C3 | C2 |
| 06 XOR | C1 | C1 | C1 | C1 | O | — | C5 | C2 | C3 | C2 |
| 07 Join3 | C1 | C1 | C1 | C1 | O | C5 | — | O | C3 | C2 |
| 08 Plans | C2 | C2 | O | C2 | C2 | C2 | O | — | O | C2 |
| 09 Workspace | C3 | C3 | C3 | C3 | C3 | C3 | C3 | O | — | C3 |
| 10 LRU | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C3 | — |
| 11 Roulette cache | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C3 | X1 |
| 12 TinyLFU | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C3 | C2 |
| 13 SIEVE | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C3 | X1 |
| 14 Génération | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C3 | C4 |
| 15 Précompile | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C3 | C4 |
| 16 DAG/mémo | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C2 | C3 | C2 |
| 17 Facteurs | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 18 Sous-espace | C6 | C6 | C6 | C6 | C6 | C6 | C6 | C2 | C3 | C2 |
| 19 TT | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 20 ZDD | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 21 Trie | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 22 Matrices/GFFT | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 23 E-graphs | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C2 | C3 | C2 |
| 24 Replay | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C2 | C3 | C2 |
| 25 Pruning approx. | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 |
| 26 HPO | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 |
| 27 Threads | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 28 Processus | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 29 GPU | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 30 Masques | C6 | C6 | C6 | C6 | C6 | C6 | C6 | C2 | C3 | C2 |
| 31 Rang binaire | C7 | C7 | C7 | C7 | C7 | C7 | C7 | C2 | C3 | C2 |
| 32 Secteurs | C8 | C8 | C8 | C8 | C8 | C8 | C8 | C2 | C3 | C2 |
| 33 Radical | C9 | C9 | C9 | C9 | C9 | C9 | C9 | C2 | C3 | C2 |
| 34 Polynôme | C10 | C10 | C10 | C10 | C10 | C10 | C10 | C2 | C3 | C2 |
| 35 Pfaffien | C10 | C10 | C10 | C10 | C10 | C10 | C10 | C2 | C3 | C2 |
| 36 Gram croisée | C10 | C10 | C10 | C10 | C10 | C10 | C10 | C2 | C3 | C2 |
| 37 Gaussien | C10 | C10 | ? | ? | ? | ? | ? | C2 | C3 | C2 |
| 38 Givens | C1 | C1 | C1 | C1 | C1 | C1 | C1 | C2 | C3 | C2 |
| 39 Convol. signée | C11 | C11 | C11 | C11 | C11 | C11 | C11 | C2 | C3 | C2 |
| 40 Bilinéaire | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C2 | C3 | C2 |
| 41 Superoptim. | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C2 | C3 | C2 |
| 42 Wavefront | C17 | C17 | C17 | C17 | C17 | C17 | C17 | C2 | C3 | C2 |
| 43 ART | ? | C18 | ? | ? | ? | C18 | C18 | C2 | C3 | C2 |
| 44 CRT | C14 | C14 | C14 | C14 | C14 | C14 | C14 | C2 | C3 | C2 |
| 45 Prédicats | C15 | C15 | C15 | C15 | C15 | C15 | C15 | C2 | C3 | C2 |
| 46 Certificats | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 |

### Colonnes 11–20

| Ligne / colonne | 11 Roulette cache | 12 TinyLFU | 13 SIEVE | 14 Génération | 15 Précompile | 16 DAG/mémo | 17 Facteurs | 18 Sous-espace | 19 TT | 20 ZDD |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 Dense | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 02 Creux/tri | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 03 Grades | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 04 Récursion | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 05 Filtre grades | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 06 XOR | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 07 Join3 | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C6 | C11 | C11 |
| 08 Plans | C2 | C2 | C2 | C4 | C4 | C2 | C2 | C2 | C2 | C2 |
| 09 Workspace | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 |
| 10 LRU | X1 | C2 | X1 | C4 | C4 | C2 | C2 | C2 | C2 | C2 |
| 11 Roulette cache | — | C2 | X1 | C4 | C4 | C2 | C2 | C2 | C2 | C2 |
| 12 TinyLFU | C2 | — | C2 | C4 | C4 | C2 | C2 | C2 | C2 | C2 |
| 13 SIEVE | X1 | C2 | — | C4 | C4 | C2 | C2 | C2 | C2 | C2 |
| 14 Génération | C4 | C4 | C4 | — | O | C4 | C4 | C4 | C4 | C4 |
| 15 Précompile | C4 | C4 | C4 | O | — | C4 | C4 | C4 | C4 | C4 |
| 16 DAG/mémo | C2 | C2 | C2 | C4 | C4 | — | C5 | C5 | C5 | C5 |
| 17 Facteurs | C2 | C2 | C2 | C4 | C4 | C5 | — | C6 | C11 | C11 |
| 18 Sous-espace | C2 | C2 | C2 | C4 | C4 | C5 | C6 | — | C11 | C11 |
| 19 TT | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C11 | — | ? |
| 20 ZDD | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C11 | ? | — |
| 21 Trie | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C11 | C11 | C11 |
| 22 Matrices/GFFT | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C11 | C11 | C11 |
| 23 E-graphs | C2 | C2 | C2 | C4 | C4 | C5 | C5 | C5 | C5 | C5 |
| 24 Replay | C2 | C2 | C2 | C4 | C4 | C5 | ? | ? | ? | ? |
| 25 Pruning approx. | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 |
| 26 HPO | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 |
| 27 Threads | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 28 Processus | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 29 GPU | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 30 Masques | C2 | C2 | C2 | C4 | C4 | C5 | C6 | C6 | ? | C6 |
| 31 Rang binaire | C2 | C2 | C2 | C4 | C4 | C5 | ? | C7 | ? | ? |
| 32 Secteurs | C2 | C2 | C2 | C4 | C4 | C5 | C8 | C8 | ? | ? |
| 33 Radical | C2 | C2 | C2 | C4 | C4 | C5 | C9 | C9 | C9 | C9 |
| 34 Polynôme | C2 | C2 | C2 | C4 | C4 | C5 | C10 | C10 | C10 | ? |
| 35 Pfaffien | C2 | C2 | C2 | C4 | C4 | C5 | C10 | C10 | ? | ? |
| 36 Gram croisée | C2 | C2 | C2 | C4 | C4 | C5 | C10 | C10 | ? | ? |
| 37 Gaussien | C2 | C2 | C2 | C4 | C4 | C5 | C10 | C10 | ? | ? |
| 38 Givens | C2 | C2 | C2 | C4 | C4 | C5 | C1 | C1 | C1 | C1 |
| 39 Convol. signée | C2 | C2 | C2 | C4 | C4 | C5 | C11 | C11 | C11 | C11 |
| 40 Bilinéaire | C2 | C2 | C2 | C4 | C4 | C5 | C16 | C16 | C16 | C16 |
| 41 Superoptim. | C2 | C2 | C2 | C4 | C4 | C5 | C16 | C16 | C16 | C16 |
| 42 Wavefront | C2 | C2 | C2 | C4 | C4 | C5 | C17 | C17 | C17 | C17 |
| 43 ART | C2 | C2 | C2 | C4 | C4 | C5 | C18 | C18 | ? | C18 |
| 44 CRT | C2 | C2 | C2 | C4 | C4 | C5 | C14 | C14 | C14 | C14 |
| 45 Prédicats | C2 | C2 | C2 | C4 | C4 | C5 | C15 | C15 | ? | ? |
| 46 Certificats | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 |

### Colonnes 21–30

| Ligne / colonne | 21 Trie | 22 Matrices/GFFT | 23 E-graphs | 24 Replay | 25 Pruning approx. | 26 HPO | 27 Threads | 28 Processus | 29 GPU | 30 Masques |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 Dense | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 02 Creux/tri | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 03 Grades | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 04 Récursion | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 05 Filtre grades | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 06 XOR | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 07 Join3 | C11 | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 08 Plans | C2 | C2 | C2 | C2 | C12 | C19 | C13 | C13 | C13 | C2 |
| 09 Workspace | C3 | C3 | C3 | C3 | C12 | C19 | C13 | C13 | C13 | C3 |
| 10 LRU | C2 | C2 | C2 | C2 | C12 | C19 | C13 | C13 | C13 | C2 |
| 11 Roulette cache | C2 | C2 | C2 | C2 | C12 | C19 | C13 | C13 | C13 | C2 |
| 12 TinyLFU | C2 | C2 | C2 | C2 | C12 | C19 | C13 | C13 | C13 | C2 |
| 13 SIEVE | C2 | C2 | C2 | C2 | C12 | C19 | C13 | C13 | C13 | C2 |
| 14 Génération | C4 | C4 | C4 | C4 | C12 | C19 | C13 | C13 | C13 | C4 |
| 15 Précompile | C4 | C4 | C4 | C4 | C12 | C19 | C13 | C13 | C13 | C4 |
| 16 DAG/mémo | C5 | C5 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C5 |
| 17 Facteurs | C11 | C11 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C6 |
| 18 Sous-espace | C11 | C11 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C6 |
| 19 TT | C11 | C11 | C5 | ? | C12 | C19 | C13 | C13 | C13 | ? |
| 20 ZDD | C11 | C11 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C6 |
| 21 Trie | — | C11 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C6 |
| 22 Matrices/GFFT | C11 | — | C5 | ? | C12 | C19 | C13 | C13 | C13 | ? |
| 23 E-graphs | C5 | C5 | — | C5 | C12 | C19 | C13 | C13 | C13 | C5 |
| 24 Replay | C5 | ? | C5 | — | C12 | C19 | C13 | C13 | C13 | C5 |
| 25 Pruning approx. | C12 | C12 | C12 | C12 | — | C19 | C12 | C12 | C12 | C12 |
| 26 HPO | C19 | C19 | C19 | C19 | C19 | — | C19 | C19 | C19 | C19 |
| 27 Threads | C13 | C13 | C13 | C13 | C12 | C19 | — | C13 | C13 | C13 |
| 28 Processus | C13 | C13 | C13 | C13 | C12 | C19 | C13 | — | C13 | C13 |
| 29 GPU | C13 | C13 | C13 | C13 | C12 | C19 | C13 | C13 | — | C13 |
| 30 Masques | C6 | ? | C5 | C5 | C12 | C19 | C13 | C13 | C13 | — |
| 31 Rang binaire | C7 | ? | C5 | ? | C12 | C19 | C13 | C13 | C13 | C7 |
| 32 Secteurs | ? | C8 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C8 |
| 33 Radical | C9 | C9 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C9 |
| 34 Polynôme | ? | C10 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C10 |
| 35 Pfaffien | ? | C10 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C10 |
| 36 Gram croisée | ? | C10 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C10 |
| 37 Gaussien | ? | C10 | C5 | ? | C12 | C19 | C13 | C13 | C13 | ? |
| 38 Givens | C1 | C1 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C1 |
| 39 Convol. signée | C11 | C11 | C5 | ? | C12 | C19 | C13 | C13 | C13 | C11 |
| 40 Bilinéaire | C16 | C16 | C5 | C16 | C12 | C19 | C13 | C13 | C13 | C16 |
| 41 Superoptim. | C16 | C16 | C5 | C16 | C12 | C19 | C13 | C13 | C13 | C16 |
| 42 Wavefront | C17 | C17 | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C17 |
| 43 ART | C18 | ? | C5 | C5 | C12 | C19 | C13 | C13 | C13 | C18 |
| 44 CRT | C14 | C14 | C5 | C14 | C12 | C19 | C13 | C13 | C13 | C14 |
| 45 Prédicats | ? | C15 | C5 | C15 | C12 | C19 | C13 | C13 | C13 | C15 |
| 46 Certificats | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 |

### Colonnes 31–40

| Ligne / colonne | 31 Rang binaire | 32 Secteurs | 33 Radical | 34 Polynôme | 35 Pfaffien | 36 Gram croisée | 37 Gaussien | 38 Givens | 39 Convol. signée | 40 Bilinéaire |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 Dense | C7 | C8 | C9 | C10 | C10 | C10 | C10 | C1 | C11 | C16 |
| 02 Creux/tri | C7 | C8 | C9 | C10 | C10 | C10 | C10 | C1 | C11 | C16 |
| 03 Grades | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 04 Récursion | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 05 Filtre grades | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 06 XOR | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 07 Join3 | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 08 Plans | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 |
| 09 Workspace | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 |
| 10 LRU | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 |
| 11 Roulette cache | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 |
| 12 TinyLFU | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 |
| 13 SIEVE | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 | C2 |
| 14 Génération | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 |
| 15 Précompile | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 | C4 |
| 16 DAG/mémo | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 |
| 17 Facteurs | ? | C8 | C9 | C10 | C10 | C10 | C10 | C1 | C11 | C16 |
| 18 Sous-espace | C7 | C8 | C9 | C10 | C10 | C10 | C10 | C1 | C11 | C16 |
| 19 TT | ? | ? | C9 | C10 | ? | ? | ? | C1 | C11 | C16 |
| 20 ZDD | ? | ? | C9 | ? | ? | ? | ? | C1 | C11 | C16 |
| 21 Trie | C7 | ? | C9 | ? | ? | ? | ? | C1 | C11 | C16 |
| 22 Matrices/GFFT | ? | C8 | C9 | C10 | C10 | C10 | C10 | C1 | C11 | C16 |
| 23 E-graphs | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 | C5 |
| 24 Replay | ? | ? | ? | ? | ? | ? | ? | ? | ? | C16 |
| 25 Pruning approx. | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 | C12 |
| 26 HPO | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 | C19 |
| 27 Threads | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 28 Processus | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 29 GPU | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 | C13 |
| 30 Masques | C7 | C8 | C9 | C10 | C10 | C10 | ? | C1 | C11 | C16 |
| 31 Rang binaire | — | C8 | C7 | C10 | ? | ? | ? | C7 | C7 | C16 |
| 32 Secteurs | C8 | — | C8 | C8 | ? | ? | ? | C8 | ? | C16 |
| 33 Radical | C7 | C8 | — | C9 | C10 | C10 | ? | C9 | C9 | C16 |
| 34 Polynôme | C10 | C8 | C9 | — | ? | ? | C10 | ? | ? | C16 |
| 35 Pfaffien | ? | ? | C10 | ? | — | C10 | ? | C10 | ? | C16 |
| 36 Gram croisée | ? | ? | C10 | ? | C10 | — | ? | C1 | ? | C16 |
| 37 Gaussien | ? | ? | ? | C10 | ? | ? | — | C10 | ? | C16 |
| 38 Givens | C7 | C8 | C9 | ? | C10 | C1 | C10 | — | C11 | C16 |
| 39 Convol. signée | C7 | ? | C9 | ? | ? | ? | ? | C11 | — | C16 |
| 40 Bilinéaire | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C16 | — |
| 41 Superoptim. | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C16 | C16 |
| 42 Wavefront | C17 | C17 | C17 | C17 | C17 | C17 | C17 | C17 | C17 | C16 |
| 43 ART | C18 | ? | ? | ? | ? | ? | ? | ? | ? | C16 |
| 44 CRT | C14 | C14 | C14 | C14 | C14 | C14 | ? | C14 | C14 | C16 |
| 45 Prédicats | C15 | C15 | C15 | C15 | C15 | C15 | ? | C15 | C15 | C16 |
| 46 Certificats | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 | C20 |

### Colonnes 41–46

| Ligne / colonne | 41 Superoptim. | 42 Wavefront | 43 ART | 44 CRT | 45 Prédicats | 46 Certificats |
|---|---|---|---|---|---|---|
| 01 Dense | C16 | C17 | ? | C14 | C15 | C20 |
| 02 Creux/tri | C16 | C17 | C18 | C14 | C15 | C20 |
| 03 Grades | C16 | C17 | ? | C14 | C15 | C20 |
| 04 Récursion | C16 | C17 | ? | C14 | C15 | C20 |
| 05 Filtre grades | C16 | C17 | ? | C14 | C15 | C20 |
| 06 XOR | C16 | C17 | C18 | C14 | C15 | C20 |
| 07 Join3 | C16 | C17 | C18 | C14 | C15 | C20 |
| 08 Plans | C2 | C2 | C2 | C2 | C2 | C20 |
| 09 Workspace | C3 | C3 | C3 | C3 | C3 | C20 |
| 10 LRU | C2 | C2 | C2 | C2 | C2 | C20 |
| 11 Roulette cache | C2 | C2 | C2 | C2 | C2 | C20 |
| 12 TinyLFU | C2 | C2 | C2 | C2 | C2 | C20 |
| 13 SIEVE | C2 | C2 | C2 | C2 | C2 | C20 |
| 14 Génération | C4 | C4 | C4 | C4 | C4 | C20 |
| 15 Précompile | C4 | C4 | C4 | C4 | C4 | C20 |
| 16 DAG/mémo | C5 | C5 | C5 | C5 | C5 | C20 |
| 17 Facteurs | C16 | C17 | C18 | C14 | C15 | C20 |
| 18 Sous-espace | C16 | C17 | C18 | C14 | C15 | C20 |
| 19 TT | C16 | C17 | ? | C14 | ? | C20 |
| 20 ZDD | C16 | C17 | C18 | C14 | ? | C20 |
| 21 Trie | C16 | C17 | C18 | C14 | ? | C20 |
| 22 Matrices/GFFT | C16 | C17 | ? | C14 | C15 | C20 |
| 23 E-graphs | C5 | C5 | C5 | C5 | C5 | C20 |
| 24 Replay | C16 | C5 | C5 | C14 | C15 | C20 |
| 25 Pruning approx. | C12 | C12 | C12 | C12 | C12 | C20 |
| 26 HPO | C19 | C19 | C19 | C19 | C19 | C20 |
| 27 Threads | C13 | C13 | C13 | C13 | C13 | C20 |
| 28 Processus | C13 | C13 | C13 | C13 | C13 | C20 |
| 29 GPU | C13 | C13 | C13 | C13 | C13 | C20 |
| 30 Masques | C16 | C17 | C18 | C14 | C15 | C20 |
| 31 Rang binaire | C16 | C17 | C18 | C14 | C15 | C20 |
| 32 Secteurs | C16 | C17 | ? | C14 | C15 | C20 |
| 33 Radical | C16 | C17 | ? | C14 | C15 | C20 |
| 34 Polynôme | C16 | C17 | ? | C14 | C15 | C20 |
| 35 Pfaffien | C16 | C17 | ? | C14 | C15 | C20 |
| 36 Gram croisée | C16 | C17 | ? | C14 | C15 | C20 |
| 37 Gaussien | C16 | C17 | ? | ? | ? | C20 |
| 38 Givens | C16 | C17 | ? | C14 | C15 | C20 |
| 39 Convol. signée | C16 | C17 | ? | C14 | C15 | C20 |
| 40 Bilinéaire | C16 | C16 | C16 | C16 | C16 | C20 |
| 41 Superoptim. | — | C16 | C16 | C16 | C16 | C20 |
| 42 Wavefront | C16 | — | C17 | C14 | C15 | C20 |
| 43 ART | C16 | C17 | — | C14 | C15 | C20 |
| 44 CRT | C16 | C14 | C14 | — | C15 | C20 |
| 45 Prédicats | C16 | C15 | C15 | C15 | — | C20 |
| 46 Certificats | C20 | C20 | C20 | C20 | C20 | — |

Contrôle de complétude : 46 × 46 cellules, diagonale identifiée, symétrie vérifiée ; 1 035 paires distinctes. Répartition analytique : 7 compatibles par construction, 948 conditionnelles, 3 alternatives de remplacement incompatibles au même niveau, 77 compositions non démontrées. Ce décompte ne compte aucun benchmark ni ne donne un taux de succès.



## Incompatibilités et compositions importantes à ne pas masquer

| Association / tentation | Verdict motivé | Expérience obligatoire |
|---|---|---|
| Rang binaire → backend Clifford standard de dimension d | **Incompatible en général sans transporter la loi** : deux générateurs comprimés peuvent commuter, avoir un carré nul ou un facteur non unitaire. Le grade ambiant n'est pas le popcount comprimé. | N1 : e₁₂ et e₃₄ commutent alors que deux vecteurs orthogonaux anticommutent ; métriques scalées et radicales. |
| Rang binaire + filtrage de grades / join3 | Conditionnel : le XOR se transporte, mais le grade et c(I,J) restent ambiants. Le plan join3 actuel n'accepte pas automatiquement ce nouveau cocycle. | Comparer les mêmes sorties, y compris grades élevés et quatre directions toutes actives avec petit rang binaire. |
| Rang binaire + changement de base Givens | Conditionnel : un changement vectoriel général n'est pas une application F₂-linéaire sur les masques et peut détruire la compression. Recalcul après transformation. | N1/N8 : cartes avant/après et coût total ; comparer les deux ordres, refuser le certificat périmé. |
| Réduction de secteurs + produit complet arbitraire | **Incompatible avec suppression de secteurs** si la sortie attend l'élément général. Exact seulement pour le contrat sectoriel déclaré ou après recomposition suffisante. | N2 : opérateur qui quitte le secteur, requête hors secteur, secteurs non centraux. |
| Radical PGA + directions nulles CGA | **Incompatible sans preuve de radical**. Un vecteur nul peut avoir un produit scalaire non nul avec un autre vecteur. | N3 : G=[[0,1],[1,0]] non dégénérée doit être rejetée par le filtre radical. |
| Pfaffien + produit multivecteur complet | **Incompatible comme remplacement total**. Il donne une sortie scalaire spécialisée ; autres sorties demandent d'autres voies. | N5 : même chaîne, demander scalaire puis un grade non nul et vérifier admission/repli. |
| Pfaffien + changement de base | Conditionnel favorable : transporter simultanément vecteurs et métrique permet de calculer les contractions dans la base la moins chère. | N5/N8 : invariance des produits scalaires, congruence exacte et coût de conversion. |
| Gram de faible rang + élagage exact | Conditionnel aux facteurs décomposables et au rang exact. Un rang numérique par SVD n'autorise pas suppression exacte. | N6 : matrices presque singulières de rang plein ; coefficients rationnels adversariaux. |
| Gaussien + action matricielle seule | **Incompatible pour restituer l'élément algébrique** si signe/phase perdus. Les rotors R et −R ont même action. | N7 : cycle donnant −1 avec action identité ; suivre amplitude et phase. |
| TT + rang binaire / gaussien / ZDD | Non démontré comme composition compacte générale ; chaque conversion peut exploser les rangs ou le DAG. | T1/T6 : taille avant/après, borne préalable et refus propre ; expansion témoin seulement en petite dimension. |
| Synthèse bilinéaire + arithmétique flottante | Exactitude algébrique possible, mais autre ordre d'addition et de multiplication. Bit-identité IEEE non présumée. | N10 : preuve rationnelle puis erreurs/cancellation/NaN dans le contrat FP choisi. |
| Pruning heuristique + prédicat certifié | **Incompatible sans encadrement complet ou reprise exacte**. Une erreur rare peut changer le signe près de zéro. | N15/T7 : erreur adversariale changeant la décision ; reprise depuis les opérandes originaux. |
| Threads + workspace unique mutable | **Incompatible en accès concurrent** ; plan immutable partageable, buffers par worker. | T3/T8 : tests de races, résultat aliasé, budget × nombre de workers. |
| LRU + roulette ou SIEVE au même niveau | Alternatives pour la même décision de victime. TinyLFU, qui décide l'admission, peut en revanche se combiner à une politique d'éviction. | T2 : même trace, graines enregistrées, budgets identiques, admission séparée d'éviction. |
| C++ vs Julia utilisant des combinaisons différentes | **Incompatible avec une conclusion sur le langage** ; comparaison de stratégies séparée. | T11 : fingerprint du contrat, plan et ordre de sommation ; mêmes entrées/sorties/horizon. |

## Tests solo : quinze nouvelles expériences conservées dans le registre

Les priorités indiquent l'ordre d'investigation, jamais une élimination définitive. Chaque technique reçoit un essai positif structuré, un cas banal où elle devrait perdre, un cas limite et un test de refus hors domaine. Une technique perdante reste dans le tableau de résultats avec la plage explorée et la raison du coût.

| Test | Piste / priorité | Oracle et jeux de données | Coût et échec recherchés |
|---|---|---|---|
| N1 | Rang binaire / P1 | Élimination F₂, encode/decode bijectifs, fermeture XOR ; oracle Clifford sur signatures +/−/0 et diagonales rationnelles ; rang d=0…min(n,dmax), masques répartis sur toutes les directions ; rang croissant au cours de la trace | Détection, dictionnaire, cocycle, plans 2ᵈ/4ᵈ éventuels, coût d'invalidation. Ne jamais allouer 4ᵈ sans garde. |
| N2 | Secteurs / P2 | Projecteurs idempotents/orthogonaux, involutions commutantes ; commuter les opérations et vérifier bloc demandé contre calcul complet petit n ; cas quittant le secteur | Détection de symétries, projection et recomposition ; centre trivial vs grand centre ; s=0…smax symétries. |
| N3 | Radical / P1 | Certifier G·R=0, tester J^(r+1)=0 ; inverses gauche et droit de A₀+N ; r=0…n et filtres de degrés ; contre-exemple CGA | Décomposition de base, taille des blocs, séries finies contre inverse général ; A₀ singulier et absence d'accélération r=0. |
| N4 | Faible degré / P2 | A²=λ1 certifié, cas anticommutants et presque anticommutants ; μ(A)=0 exact ; inverse des deux côtés ; exponentielle contre précision élevée avec erreur déclarée | Recherche de μ incluse ; un appel vs puissances/chaînes longues ; élément changeant invalidant l'identité. |
| N5 | Pfaffien / P1 | Scalaire de 2m vecteurs par oracle produit ; m=0,1,2, chaînes nulles, permutations, signature indéfinie ; exact rationnel puis flottant conditionné/mal conditionné | Construction Gram + Pfaffien + extraction ; longueur 2m séparée de n ; signe et pivot nul ; comparer aussi les produits scalaires déjà disponibles. |
| N6 | Rang de Gram / P2 | Blades factorisés exacts ; C=UV de rang connu ρ ; disparition des contributions k>ρ et produit complet témoin ; presque bas rang | Certification, mineurs/angles, expansion et économies réelles ; r,s,ρ balayés ; angles principaux réservés d'abord à l'euclidien. |
| N7 | Gaussien / P2 | Chaînes quadratiques fermées, action et coefficients petits n ; signe −R ; phase et échelle ; sommes et opérations sortant de la famille | Préparation et composition compacte, nombre de sorties non gaussiennes 0…k ; reconstruction demandée et coût du repli. |
| N8 | Givens extérieur / P1 | ΛᵏQ contre déterminants/matrices induites/outermorphism ; grades 0,1,⌊n/2⌋,n ; Q rotations, permutations, det −1 géré et échelles séparées | Factorisation, nombre de passes, trafic, densification ; coefficient demandé seul vs bloc entier ; support qui devient dense. |
| N9 | Convolution signée / P3 | Wedge entier comparé à oracle direct ; signes antisymétriques, parties paires/impaires ; petits n exhaustifs sur blades | Conversion et mémoire dense ; aucune revendication de borne pratique avant algorithme faithful ; O* masque polynômes/coût binaire. |
| N10 | Synthèse bilinéaire / P2 | Tenseurs petits PGA/CGA/supports ; reconstruire exactement T=ΣᵣW·U·V sur Q/Z ; distinguer corps finis | Recherche hors ligne, taille noyau, multiplications/additions, registres, compile ; faux transfert caractéristique 2 rejeté. |
| N11 | Superoptimisation / P3 | Petits signes/parités/accumulations ; preuve SMT ou exhaustive dans domaine borné, équivalence LLVM selon flags | Budget recherche, ISA, taille et vitesse ; perte hors architecture et traitement de NaN/−0. |
| N12 | Wavefront / P3 | Même liste multiensemble des contributions utiles que DFS ; profondeur/front hybride ; trace de sorties identiques | Files, compactage, tri, divergence et synchronisation ; batch=1 témoin défavorable ; mémoire maximale du front. |
| N13 | ART / P3 | Appartenance, itération, mutations identiques à dictionnaire/tri ; index réellement utilisé dans jointure | Supports préfixés/aléatoires à cardinal égal ; construction, traversée, cache CPU ; zero effet attendu sur récursion virtuelle seule. |
| N14 | Multimodulaire / P2 | Produit/déterminant/inverse sur Z/Q contre BigInt/rationnel ; reconstruction unique bornée ; mauvais premiers | Bits de coefficient 8…croissance adaptative ; nombre de modules, reconstruction et threads ; nullités modulaires trompeuses. |
| N15 | Prédicats filtrés / P2 | Signes exacts d'orientations/contractions ciblées ; entrées rationnelles ou flottants interprétés exactement ; cas proches de zéro | Taux de filtre concluant, coût fallback, décisions incorrectes doit rester zéro ; inclure tous les coûts antérieurs. |

## Contrôles communs et combinaisons

| Test | Protocole mesurable |
|---|---|
| T0 | Oracle indépendant (mots de Clifford en petit n, Z/Q sans overflow), mêmes contrats ; propriétés nécessaires mais non suffisantes : associativité, bilinéarité, anticommutation, aller-retour, relations de grade. Float64 mesuré séparément avec modèle d'erreur. |
| T1 | Conversion isolée puis coût total : entrée → format → opération → sortie demandée. Trace native persistante et trace avec conversion à chaque appel, tous deux publiés. |
| T2 | Supports fixes, croissance, balayage sans répétition, phases et remplacement brutal ; coefficients changés à chaque étape ; aucun accès à une valeur périmée. LRU/roulette/TinyLFU/SIEVE/aucun cache à budgets égaux. |
| T3 | Allocations après chauffe, pic RSS, mémoire retenue/libérée, aliasing et dépassement anticipé ; quota global subdivisé entre plans/buffers/files/caches/processus. |
| T4 | Processus frais, préparation, premier JIT, exécution chaude, code conservé et redémarrage ; H=1,32,1024,10000 et continuations si coût admissible. Artefacts périmés testés. |
| T5 | DAG avec/sans répétition, requêtes 1/4/8/64/toutes ; coefficients mutables relus ; expression réassociée vérifiée sous contrat exact et FP séparément. |
| T6 | Certificat fourni au constructeur vs détecté au runtime ; propriété conservée, perdue, rétablie ; compteur des gardes et coût de chaque revalidation. |
| T7 | Trajectoires longues, amplifiantes, dissipatives, cancellation ; erreur maximale/finale et distribution des graines ; contributions réellement évitées et coût du replay comptés. Aucune tolérance ne valide une API dite exacte sur Z/Q. |
| T8 | 1/2/4/8/16 threads selon CPU, 1/2/4/8 processus sous RAM, GPU si backend présent ; BLAS/threads internes enregistrés ; synchroniser GPU ; charge système et transferts conservés. |
| T9 | Oracle de coût distinct de l'oracle mathématique ; holdout familles métriques/supports/structures ; variants isomorphes dans le même groupe ; regret, overhead, erreurs d'admission, mémoire, SHAP sur modèle réellement entraîné. |
| T10 | Ordre des transformations : A→B puis B→A lorsque défini ; sorties communes exactes, certificats invalidés/régénérés ; triangle de conversions et composition à trois techniques. |
| T11 | Comparaison C++/Julia à stratégie appariée : mêmes supports, masque logique, précision, sorties, préparation, pruning, ordre et horizon ; voie Mvec amont séparée d'un kernel expérimental porté. |

Les combinaisons prioritaires constituent des hypothèses précises :

| Lot | Assemblage candidat | Hypothèse à tester et contrôle négatif |
|---|---|---|
| K1 | 31 rang binaire → 06/07 XOR/join3 → 08 plan → 09 workspace | Masques ambiants larges et faible rang récurrent ; contrôle rang presque n et supports changeants. Adapter c et le grade avant le plan. |
| K2 | 33 radical → 05 filtration exacte → 08 plan → 09 workspace | PGA et chaînes où degré radical rejette des blocs avant expansion ; contrôle r=0 et CGA nulle non radicale. |
| K3 | 35 Pfaffien + 16 DAG de produits scalaires + 09 workspace | Chaînes longues partageant les vecteurs/contractions ; contrôle chaîne courte sans partage et Gram mal conditionnée. |
| K4 | 38 Givens → 03 blocs par grades → 27 lots/threads | Réutilisation de Q et grades pleins ; contrôle un coefficient ciblé ou support très creux. |
| K5 | 17 facteurs → 36 rang croisé → 46 certificats → 16 DAG | Interaction faible fournie par construction ; contrôle lames générales et coût de certification maximal. |
| K6 | 34 identité polynomiale + 33 radical + 08 plans | Inverses et puissances répétées dans algèbre dégénérée ; vérifier relation après chaque mutation. La série de N et la relation de A ne sont pas interchangeables. |
| K7 | 32 secteurs + 31 compression binaire + 37 gaussien | Commencer par vérifier domaines communs et phase ; aucune présomption que trois réductions sont simultanément compactes. Lot de faisabilité avant timings. |
| K8 | 19 TT ou 20 ZDD + 18 réduction active | Mesurer rang/largeur et ordre des directions ; contrôle entrées aléatoires ; trois représentations concurrentes puis conversions. |
| K9 | 40 bilinéaire → 41 superoptimisation → 14 génération → 15 catalogue | Petit noyau extrêmement répété ; coûts hors ligne et de build publiés ; contrôle code direct compilé identiquement. |
| K10 | 04/05 récursion → 42 fronts → 27 CPU ou 29 GPU | Lots irréguliers assez gros ; contrôle DFS batch=1 ; budgets files globaux et ordre FP. |
| K11 | 06 jointure → 43 ART ou 21 trie ou 02 tri → 08 plan | Index changeant vs index réutilisé ; coût d'accès peut devenir inutile une fois tous les chemins précompilés. |
| K12 | 44 CRT → 28 processus / 27 threads → 09 workspace | Gros coefficients exacts et modules indépendants ; contrôle petits entiers où conversion domine. |
| K13 | 45 filtres → 16 DAG paresseux → 44 secours exact | Signes faciles majoritaires et résultats intermédiaires partagés ; contrôle quasi-dégénérescence généralisée. |
| K14 | 12 TinyLFU + 10 LRU ou 13 SIEVE + 08 plans | Admission et éviction séparées ; contrôle balayage, changement brutal et absence de répétition. |
| K15 | 26 HPO sur les assemblages admissibles K1–K14 | Le sélecteur choisit un pipeline avec conversions, pas une somme de gains solo ; mesurer coût de sélection et retombée hors corpus. |

## Dimensions, coût complet et déroulement de la campagne

Chaque famille possède une progression **n=2,3,4,… sans saut** jusqu'à sa première limite de ressources déclarée. La limite est propre à un contrat et à une charge : dense plein, grade central plein, creux aléatoire, rang binaire fixé, TT de rang fixé, radical fixé, chaînes gaussiennes ou sorties scalaires n'ont pas la même limite. Un essai inapplicable reste enregistré `not_applicable`, et non traité comme une victoire ni comme une panne. Un arrêt mémoire/temps est conservé avec l'estimation et la limite. Aucune dimension au-delà de cet arrêt n'est déclarée étudiée dans cette famille.

L'exploration commence par les faibles budgets et les quinze solos ; ensuite paires prioritaires K1–K14 avec ablation **référence, A seule, B seule, A+B** sur la même instance et le même contrat. Pour un triple on mesure les trois paires admises et le triple. On étend aux paires C/? restantes par domaine commun, même si elles semblent marginales ; un budget de faisabilité borné doit fournir soit un prototype exact, soit un contre-exemple de contrat, soit un résultat « non résolu sous budget ». Aucun filtre statistique ne supprime à jamais une technique qui perd sur le premier petit corpus.

Les axes structurels varient indépendamment de n : occupation dense/creuse, grades, nombre de sorties, largeur des masques, d binaire, r radical, ρ d'interaction, degré polynomial, rang TT, largeur DAG, longueur de chaîne, nombre d'opérations non gaussiennes, taille du lot, threads, précision et nombre de bits des coefficients. Les dimensions ajoutées mais inactives ne sont pas présentées comme davantage de complexité mathématique.

GaramonBench doit porter ces contrats et paramètres dans ses manifests DrWatson et émettre les échantillons bruts PerfChecker, gardes et motifs de refus. La campagne exploratoire sous processus Étendue3D concurrents est limitée à **quatre threads ou workers au plus**, avec le nombre réellement employé consigné ; elle sert à sélectionner des pistes, sans figer les seuils de routage. La **matrice entière** de cas, y compris configurations plus larges, reste enregistrée et sera rejouée ensemble dans un environnement sans concurrence extérieure. Cette confirmation isolée utilise ordres contrebalancés, mêmes graines et horizons, plusieurs processus frais, temps/allocations/RSS, empreintes des sources et du harnais, compilateur/ISA et mémoire disponibles. La préparation et les conversions sont incluses dans le coût utilisateur, et les phases sont aussi publiées séparément.

L'espace mémoire minimal des sorties est une contrainte de contrat. Un produit général dense a 2ⁿ coefficients ; aucun raccourci ne permet de restituer explicitement cette sortie dans moins d'espace que sa taille. Une représentation comprimée, un secteur ou un scalaire constituent d'autres contrats, légitimes quand demandés. On arrête proprement avant épuisement de RAM, on libère les workspaces inutiles et on génère/nettoie une dimension C++ à la fois selon le budget déjà prévu de 256 Mio.

## Sources primaires et portée de la transposition

La pièce jointe comporte des marqueurs de citation internes sans URL. Les références suivantes ont été retrouvées indépendamment. Elles établissent leurs méthodes dans leur propre domaine ; les cellules de combinaison sont des déductions de cet audit et restent à tester dans Garamon.

| Pistes | Source consultée | Ce qu'elle soutient / limite |
|---|---|---|
| 31–32 | [PauLIB, préprint 2026](https://arxiv.org/abs/2605.25974) ; [Bravyi et al., tapering, 2017](https://arxiv.org/abs/1701.08213) ; [Gargiulo–Herringer–Zeier, 2026](https://arxiv.org/abs/2606.09773) | PauLIB décrit un encodage binaire compact de chaînes de Pauli ; les autres sources étudient réductions par symétries et invariants. La fermeture XOR des supports Clifford diagonaux est dérivée ici ; aucune équivalence générale avec `Cl(d,0)` ni gain Garamon n'en résulte automatiquement. |
| 33 | [Filimoshina–Shirokov, 2023](https://arxiv.org/abs/2301.06842) | Cadre des algèbres dégénérées. La borne J^(r+1)=0 se prouve ici en choisissant une base du radical : tout mot avec r+1 facteurs radicaux répète une direction, dont le carré est nul ; la bilinéarité conclut. |
| 34 | [Prodanov, Mathematics 2025](https://www.mdpi.com/2227-7390/13/7/1106) | Polynômes minimaux et inverses dans les algèbres non dégénérées. La généralisation de l'algorithme à un radical n'est pas supposée. |
| 35 | [Wilmot, thèse, Adelaide](https://digital.library.adelaide.edu.au/items/38b1b85d-ff40-4c49-85a5-475ea9246947) ; [Wimmer, 2011](https://arxiv.org/abs/1102.3440) | Lien Clifford/Pfaffien et algorithmes numériques de Pfaffien. L'identité scalaire se vérifie aussi récursivement par les appariements signés ; racine de déterminant insuffisante. |
| 36 | Déduction par mineurs de contractions | Les mineurs d'ordre k>ρ sont nuls lorsque C a rang ρ ; il faut encore tester le développement complet, les signes et les formes d'entrée. Aucune mesure de gain attribuée à une publication. |
| 37 | [Bravyi, 2004](https://arxiv.org/abs/quant-ph/0404180) | Représentation gaussienne en variables de Grassmann et cartes gaussiennes. Extension à toutes signatures, suivi de phase et sorties non gaussiennes restent des travaux dédiés. |
| 38 | [ffsim, code orbital_rotation](https://qiskit-community.github.io/ffsim/_modules/ffsim/gates/orbital_rotation.html) | Décomposition de rotations orbitales et application Givens. La transposition à l'extension extérieure Julia nécessite orientations et gestion de tous les facteurs de Q. |
| 39,22 | [Włodarczyk, IPEC 2016](https://drops.dagstuhl.de/storage/00lipics/lipics-vol063-ipec2016/LIPIcs.IPEC.2016.29/LIPIcs.IPEC.2016.29.pdf) | Convolution non commutative via Clifford ; borne asymptotique O*(2^(ωn/2)) dans son cadre. Aucun seuil pratique déduit. |
| 40 | [Fawzi et al., AlphaTensor, Nature 2022](https://doi.org/10.1038/s41586-022-05172-4) | Recherche de décompositions bilinéaires ; domaines de coefficients et vitesse machine importent. |
| 41 | [Liu–Mada–Regehr, Minotaur](https://users.cs.utah.edu/~regehr/minotaur-oopsla24.pdf) | Superoptimisation SIMD LLVM avec vérification formelle dans le modèle fixé. Pas de preuve automatique de tout le pipeline GA. |
| 42 | [Laine–Karras–Aila, NVIDIA 2013](https://research.nvidia.com/publication/2013-07_megakernels-considered-harmful-wavefront-path-tracing-gpus) | Organisation GPU en fronts de travail ; bénéfices ray tracing non transférables sans mesure GA. |
| 43 | [Leis–Kemper–Neumann, ART 2013](https://db.in.tum.de/~leis/papers/ART.pdf) | Structures d'index adaptatives en mémoire ; pertinence limitée aux index matérialisés. |
| 44 | [FLINT, matrices entières](https://flintlib.org/doc/fmpz_mat.html) | Multiplication multimodulaire, bornes et CRT ; domaine exact. |
| 45 | [CGAL, schéma paresseux exact, Pion–Fabri](https://cs.nyu.edu/exact/pap/eval/pion_fabri_generic_eval_for_EGC.pdf) ; [Lazy_exact_nt source](https://github.com/CGAL/cgal/blob/main/Number_types/include/CGAL/Lazy_exact_nt.h) | Filtrage et reprise exacte depuis expressions/données conservées. |

Cette matrice complète la roadmap ; elle ne remplace pas les rapports de performances ni leurs réserves. Le statut à mettre à jour après chaque expérience est : **non essayé**, **admissible et correct**, **rejeté hors contrat**, **correct mais sans gain sur ce régime**, **gain exploratoire**, puis éventuellement **gain confirmé isolément**.
