# Transfer Network Dynamics

Analisi della **rete dei trasferimenti calcistici** come sistema complesso, per il corso
*Data Driven Modeling of Complex Systems*.

## Domanda di ricerca

La **posizione strutturale** di un club nella rete dei trasferimenti predice la sua capacità di
**estrarre valore economico**, oltre e al di là della sua **spesa**?

È una *corsa di cavalli*: un attributo individuale del nodo (la spesa) contro una misura di rete
(la centralità), a predire lo stesso esito. La rete "si guadagna il posto" solo se la posizione
spiega ciò che la spesa da sola non spiega.

## Dati

- **Fonte:** [d2ski/football-transfers-data](https://github.com/d2ski/football-transfers-data)
  (7 leghe top europee, stagioni 2009–2021). I dati grezzi **non** sono inclusi in questo repo:
  si scaricano dalla fonte originale.
- **Snapshot di riferimento:** dati scaricati il 2025-07-15 (il dataset a monte è fermo al 2021).

## Definizioni chiave

- **Esito Y** — per ogni club-stagione, somma di `(prezzo di vendita − valore di mercato)` sulle
  vendite. Misura *quanto un club vende sopra la valutazione di mercato*: bravura di
  negoziazione/tempismo, non volume né ricchezza.
- **Frontiera della rete (doppia):**
  - *nodi*: si tengono le coppie (club, stagione) in cui il club milita in una delle 7 leghe
    coperte; le grandezze di nodo (Y, spesa) si calcolano su **tutte** le transazioni del club.
  - *archi*: il grafo si costruisce **solo** sugli archi *core-to-core* (entrambi gli estremi core),
    per non contaminare le misure di centralità con nodi osservati parzialmente.
- **Esclusioni:** prestiti (non passaggi di proprietà), ritiri (`counter_team_id = "Retired"`),
  valori-spazzatura (fee > 250M, placeholder irrealistici per il periodo 2009–2021).

## Struttura del repo

| File | Contenuto |
|---|---|
| `transfers_pre_processing.ipynb` | Notebook di preprocessing: dai dati grezzi alle due viste pulite. |
| `node_season_core.csv` | Tabella nodo-stagione (1649 righe): esito Y + attributi individuali. |
| `edge_list_core.csv` | Edge list pesata e *season-aware* (3374 archi core-to-core). |
| `club_names.csv` | Mappa `club_id → nome` per leggibilità. |

## Prossimi passi

Analisi di rete in R/igraph: costruzione dei 13 grafi stagionali, calcolo del ventaglio di misure
strutturali (betweenness topologica, in/out-degree, PageRank), e corsa di cavalli con lag
temporale posizione(t) → esito(t+1).
