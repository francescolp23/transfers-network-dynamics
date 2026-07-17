# Transfers Network Dynamics

Progetto per il corso di Data Driven Modeling of Complex Systems. Ho modellato il mercato dei trasferimenti calcistici come una rete e ho provato a rispondere a una domanda precisa.

## La domanda di ricerca

Alcuni club generano valore dal mercato senza essere ricchi: comprano giovani, li fanno crescere, li rivendono. Altri spendono e basta. Volevo capire se questa capacità dipende da quanto un club spende oppure da dove si trova nella rete degli scambi.

Detto in modo più tecnico: la posizione di un club nella rete predice il valore che estrae, oltre a quello che già si spiega con la spesa? È un confronto tra due variabili rivali — un attributo del club (la spesa) contro una misura di rete (la centralità). La rete "serve" solo se la posizione aggiunge qualcosa che la spesa da sola non cattura.

## Cosa è venuto fuori

![Mappa dei ruoli](mappa_ruoli.png)

La posizione conta davvero: nel modello con lag temporale (posizione nell'anno t, esito nell'anno t+1) la centralità resta significativa, e quando la aggiungo il peso della spesa si dimezza. Quindi parte di quello che sembrava "effetto dei soldi" era in realtà posizione.

Però l'effetto è concentrato sui grandi estrattori: la posizione predice più *quanto* estrai che *se* estrai. L'ho verificato con quattro versioni diverse dell'esito, e il segnale si comporta in modo coerente.

La cosa più interessante è che esistono due modi di estrarre valore. C'è chi lo fa intermediando (i broker, club centrali) e chi lo fa producendo talento e vendendolo direttamente (club periferici, che risultano più efficienti per euro speso). La betweenness vede bene i primi ed è cieca ai secondi — ed è proprio questa cecità che mi ha fatto scoprire la seconda via.

Nella mappa qui sopra i due assi sono la posizione (betweenness) e la direzione del flusso (vendo netto / compro netto). I broker-produttori come Porto e Benfica stanno in alto a destra, gli accumulatori come Real e City in basso a destra, e l'Athletic Bilbao — produttore puro ma periferico — quasi da solo in alto a sinistra.

## Dati

Fonte: [d2ski/football-transfers-data](https://github.com/d2ski/football-transfers-data), 7 leghe top europee, stagioni 2009–2021. I dati grezzi non sono qui dentro, si scaricano dal repo originale. Snapshot usato: luglio 2025 (il dataset a monte è comunque fermo al 2021).

## Scelte fatte che vanno spiegate

L'esito che misuro è il margine sul valore di mercato: prezzo di vendita meno la valutazione al momento della vendita. Avrei voluto usare "venduto meno comprato", ma il costo d'acquisto manca per circa due terzi del valore (acquisti troppo vecchi per essere nei dati), e metterlo a zero avrebbe inventato profitti dal nulla.

Per la rete ho tenuto solo i club delle 7 leghe coperte, e ho costruito il grafo solo sugli archi tra questi club, così le centralità non vengono falsate da squadre di cui vedo mezza attività. La betweenness la calcolo senza pesi economici, se no sarebbe circolare (l'esito è già fatto di soldi). Ho usato il lag temporale per evitare che fosse il successo a spiegare la posizione invece del contrario, e gli errori standard clusterizzati perché lo stesso club torna in più stagioni.

Sulla struttura: la rete è sparsa, connessa in un pezzo solo, con distanze brevi e pochi hub molto collegati. Non è una power law pura, la coda cala troppo in fretta — l'ho controllato in log-log.

## File

| File | Cosa contiene |
|---|---|
| `transfers_pre_processing.ipynb` | Preprocessing in Python: dai dati grezzi alle tabelle pulite. |
| `i-graph-transfers.R` | Analisi in R con igraph: grafi, misure, modelli, grafici. |
| `node_season_core.csv` | Tabella club-stagione con esito e attributi. |
| `edge_list_core.csv` | Lista degli archi per stagione. |
| `club_names.csv` | Corrispondenza id → nome club. |
| `club_season_final.csv` | Tabella finale con misure di rete, quella su cui giro i modelli. |
| `mappa_ruoli.png`, `rete_20XX.png` | Le figure principali. |

Il codice R in alcuni punti è un po' grezzo: l'ho scritto in modo iterativo mentre capivo i dati.
