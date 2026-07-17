# ============================================================
# FASE R — Passo 1: caricamento dati
# ============================================================

# Installa igraph (SOLO la prima volta; se già installato, salta questa riga)

install.packages("igraph")

library(igraph)

# Carica le due viste + la mappa nomi
edges <- read.csv("edge_list_core.csv")
nodes <- read.csv("node_season_core.csv")
names <- read.csv("club_names.csv")

# Controllo: dimensioni attese
cat("edges:", nrow(edges), "righe x", ncol(edges), "colonne\n")
cat("nodes:", nrow(nodes), "righe x", ncol(nodes), "colonne\n")
cat("names:", nrow(names), "righe\n")

# Sbirciamo la struttura della edge list
head(edges)
str(edges)



# ============================================================
# FASE R — Passo 2: primo grafo stagionale (2009, di prova)
# ============================================================

# Isola gli archi della stagione 2009
e2009 <- edges[edges$season == 2009, ]
cat("Archi 2009:", nrow(e2009), "\n")

# Costruisci il grafo DIRETTO pesato.
# Le prime due colonne (source, target) definiscono gli archi;
# le altre diventano attributi dell'arco.
g2009 <- graph_from_data_frame(
  d = e2009[, c("source", "target", "total_value", "n_transfers")],
  directed = TRUE
)

# Controlli di base
cat("Nodi:", vcount(g2009), "\n")
cat("Archi:", ecount(g2009), "\n")
cat("È diretto?", is_directed(g2009), "\n")
cat("È pesato? (ha attributo total_value):", "total_value" %in% edge_attr_names(g2009), "\n")


# Verifica: i nodi del grafo 2009 sono davvero club core?
# (i core distinti totali sono 239; i nodi di ogni stagione devono starci dentro)
core_ids <- unique(nodes$club_id)
nodi_2009 <- as.integer(V(g2009)$name)
cat("Nodi 2009 che sono nella lista core:", sum(nodi_2009 %in% core_ids), "su", length(nodi_2009), "\n")


# ============================================================
# Betweenness TOPOLOGICA sul grafo NON-DIRETTO (broker di posizione)
# ============================================================
g2009_und <- as.undirected(g2009, mode = "collapse")  # rende non-diretto

bt <- betweenness(g2009_und, directed = FALSE, weights = NA)  # weights=NA -> topologica

# Top 10 broker del mercato 2009
top <- sort(bt, decreasing = TRUE)[1:10]
top_df <- data.frame(club_id = as.integer(names(top)), betweenness = round(as.numeric(top), 1))
top_df <- merge(top_df, names, by = "club_id", all.x = TRUE)
top_df[order(-top_df$betweenness), ]





# ============================================================
# FASE R — Passo 3: misure strutturali su TUTTE le stagioni
# ============================================================
stagioni <- sort(unique(edges$season))
ris <- list()

for (s in stagioni) {
  es <- edges[edges$season == s, ]
  g  <- graph_from_data_frame(es[, c("source","target","total_value","n_transfers")],
                              directed = TRUE)
  gu <- as.undirected(g, mode = "collapse")
  
  # Betweenness topologica (broker di posizione, non-diretta, senza pesi)
  bt <- betweenness(gu, directed = FALSE, weights = NA)
  
  # Degree diretti (venditore / acquirente netto)
  out_deg <- degree(g, mode = "out")   # a quanti club VENDE
  in_deg  <- degree(g, mode = "in")    # da quanti club COMPRA
  
  df <- data.frame(
    club_id     = as.integer(names(bt)),
    season      = s,
    betweenness = as.numeric(bt),
    out_degree  = as.integer(out_deg[names(bt)]),
    in_degree   = as.integer(in_deg[names(bt)])
  )
  ris[[as.character(s)]] <- df
}

measures <- do.call(rbind, ris)
rownames(measures) <- NULL

cat("Righe totali (club-stagione con misure):", nrow(measures), "\n")
cat("Stagioni coperte:", length(unique(measures$season)), "\n")
head(measures)



# Sanity-check sulle misure
summary(measures[, c("betweenness","out_degree","in_degree")])

# Nessun valore negativo o assurdo? betweenness >= 0, degree >= 0
cat("betweenness min:", min(measures$betweenness),
    "| out max:", max(measures$out_degree),
    "| in max:", max(measures$in_degree), "\n")




#--------------------------
# Chi sono i club core SENZA posizione di rete core-to-core?
# (hanno Y ma non compaiono nel grafo di quella stagione)
key_nodes    <- paste(nodes$club_id, nodes$season)
key_measures <- paste(measures$club_id, measures$season)

mancanti <- nodes[!(key_nodes %in% key_measures), ]
cat("Club-stagione con Y ma senza rete:", nrow(mancanti), "\n")

# Che Y hanno? Sono casi particolari o normali?
summary(mancanti$Y_margin_sum)
cat("\nQuota con vendite (n_sales_tot > 0):",
    round(mean(mancanti$n_sales_tot > 0) * 100, 1), "%\n")

# Un'occhiata ai primi, con nome
mancanti_named <- merge(mancanti[, c("club_id","season","Y_margin_sum","n_sales_tot","spend_sum")],
                        names, by = "club_id", all.x = TRUE)
head(mancanti_named[order(-mancanti_named$Y_margin_sum), ], 10)









# ============================================================
# FASE R — Passo 4: unione misure + esito Y (Opzione A)
# I club core senza rete entrano con centralità/degree = 0
# ============================================================
# Left join: parti da TUTTI i club-stagione core (nodes), aggancia le misure
final <- merge(nodes, measures, by = c("club_id","season"), all.x = TRUE)

# I mancanti (150) hanno NA nelle misure -> diventano 0 (centralità core nulla)
final$betweenness[is.na(final$betweenness)] <- 0
final$out_degree[is.na(final$out_degree)]   <- 0
final$in_degree[is.na(final$in_degree)]     <- 0

cat("Righe tabella finale:", nrow(final), "\n")
cat("Con betweenness = 0:", sum(final$betweenness == 0), "\n")
cat("Colonne:", paste(names(final), collapse = ", "), "\n")
head(final)



# Salviamo la tabella finale
write.csv(final, "club_season_final.csv", row.names = FALSE)
cat("Salvata: club_season_final.csv\n")






# ============================================================
# FASE R — Passo 5: costruzione del lag  posizione(t) -> Y(t+1)
# ============================================================

# Predittori misurati in t: posizione + baseline (dalla stagione t)
pred_t <- final[, c("club_id", "season",
                    "betweenness", "out_degree", "in_degree",
                    "spend_sum", "n_sales_tot", "costzero_share")]

# Esito misurato in t+1: creo una tabella "esito" e sposto la stagione indietro di 1,
# così quando la unisco, l'esito di t+1 si allinea ai predittori di t.
esito_t1 <- final[, c("club_id", "season", "Y_margin_sum")]
esito_t1$season_pred <- esito_t1$season - 1   # Y del 2016 si aggancia ai predittori del 2015

# Unione: predittori(t) con esito(t+1)
model_df <- merge(
  pred_t,
  esito_t1[, c("club_id", "season_pred", "Y_margin_sum")],
  by.x = c("club_id", "season"),
  by.y = c("club_id", "season_pred")
)

cat("Righe con lag valido (t e t+1 entrambi presenti):", nrow(model_df), "\n")
cat("Stagioni dei predittori:", paste(sort(unique(model_df$season)), collapse=", "), "\n")
head(model_df)


# verifichiamo quante righe hanno l'esito (t+1) nelle stagioni fragili 2010-2011?
tab <- table(model_df$season)
cat("Righe per stagione-predittore:\n"); print(tab)
cat("\nRighe con predittori 2009-2010 (esito 2010-2011, Y fragile):",
    sum(model_df$season %in% c(2009, 2010)), "\n")
cat("Righe dal 2011 in poi (esito 2012+, Y solida):",
    sum(model_df$season >= 2011), "\n")







# ============================================================
# FASE R — Passo 6: campione finale del modello (Y solida, dal 2011)
# ============================================================
model_df <- model_df[model_df$season >= 2011, ]
cat("Righe campione finale:", nrow(model_df), "\n")

# Diamo un'occhiata alle distribuzioni dei predittori prima di modellare
summary(model_df[, c("Y_margin_sum", "betweenness", "spend_sum", "n_sales_tot")])





# ============================================================
# FASE R — Passo 7: MODELLO A (esplorazione) — Y continua ~ log(predittori)
# ============================================================

# Trasformazioni log(1+x): domano l'asimmetria, gestiscono gli zeri
model_df$log_betweenness <- log1p(model_df$betweenness)
model_df$log_spend       <- log1p(model_df$spend_sum)
model_df$log_nsales      <- log1p(model_df$n_sales_tot)

# --- La corsa di cavalli ---
# Cavallo baseline da solo: solo la spesa
m_spesa <- lm(Y_margin_sum ~ log_spend, data = model_df)

# Modello completo: spesa + posizione (betweenness) + controllo volume
m_full  <- lm(Y_margin_sum ~ log_spend + log_betweenness + log_nsales,
              data = model_df)

cat("=== Modello solo spesa ===\n")
print(summary(m_spesa))
cat("\n\n=== Modello completo (spesa + posizione + volume) ===\n")
print(summary(m_full))







# ============================================================
# FASE R — Passo 8: MODELLO C (principale) — logistica, estrattore sì/no
# ============================================================

# Esito binario: 1 = estrattore di valore (Y > 0), 0 = no
model_df$extractor <- as.integer(model_df$Y_margin_sum > 0)

cat("Estrattori (Y>0):", sum(model_df$extractor),
    "| Non-estrattori:", sum(model_df$extractor == 0),
    "| Quota estrattori:", round(mean(model_df$extractor)*100, 1), "%\n\n")

# --- La corsa di cavalli, versione logistica ---
# Baseline: solo spesa
c_spesa <- glm(extractor ~ log_spend, data = model_df, family = binomial)

# Completo: spesa + posizione + controllo volume
c_full  <- glm(extractor ~ log_spend + log_betweenness + log_nsales,
               data = model_df, family = binomial)

cat("=== C: solo spesa ===\n");            print(summary(c_spesa))
cat("\n=== C: completo ===\n");             print(summary(c_full))

cat("Quota estrattori (Y>0):", round(mean(model_df$extractor)*100, 1), "%\n")



install.packages("sandwich"); install.packages("lmtest")
library(sandwich); library(lmtest)

coeftest(c_full, vcov = vcovCL, cluster = ~ club_id)






# ============================================================
# FASE R — Passo 9: MODELLO B (robustezza) — Y trasformata asinh
# ============================================================
# asinh(x) = log(x + sqrt(x^2+1)): come il log ma definito su negativi e zero
model_df$y_asinh <- asinh(model_df$Y_margin_sum)

b_full <- lm(y_asinh ~ log_spend + log_betweenness + log_nsales, data = model_df)

library(sandwich); library(lmtest)
cat("=== B: Y asinh, SE clusterizzati per club ===\n")
coeftest(b_full, vcov = vcovCL, cluster = ~ club_id)








# Quanto A dipende dai POCHI valori estremi di Y?
# Rifacciamo A escludendo l'1% superiore e inferiore di Y (i mega-estrattori/svenditori)
q_lo <- quantile(model_df$Y_margin_sum, 0.01)
q_hi <- quantile(model_df$Y_margin_sum, 0.99)
trimmed <- model_df[model_df$Y_margin_sum > q_lo & model_df$Y_margin_sum < q_hi, ]

cat("Righe dopo il trim (1%-99%):", nrow(trimmed), "su", nrow(model_df), "\n\n")

a_trim <- lm(Y_margin_sum ~ log_spend + log_betweenness + log_nsales, data = trimmed)
library(sandwich); library(lmtest)
coeftest(a_trim, vcov = vcovCL, cluster = ~ club_id)









# I grandi estrattori: chi guida l'effetto della posizione?
# Prendiamo i club-stagione con Y più alta, tra quelli con betweenness non banale
big <- model_df[order(-model_df$Y_margin_sum), ]
big_named <- merge(big[, c("club_id","season","Y_margin_sum","betweenness","spend_sum")],
                   names, by = "club_id", all.x = TRUE)
big_named <- big_named[order(-big_named$Y_margin_sum), ]

cat("=== Top 20 estrattori di valore (Y in t+1) ===\n")
head(big_named, 20)




# Classifica per EFFICIENZA: estrazione di valore per euro speso
# (i selling club veri: tanto margine, poca spesa)
eff <- model_df[model_df$Y_margin_sum > 0, ]
eff$efficiency <- eff$Y_margin_sum / (eff$spend_sum + 1e6)  # +1M per evitare /0

eff_named <- merge(eff[, c("club_id","season","Y_margin_sum","spend_sum","betweenness","efficiency")],
                   names, by = "club_id", all.x = TRUE)
eff_named <- eff_named[order(-eff_named$efficiency), ]

cat("=== Top 20 per EFFICIENZA (margine / spesa) ===\n")
head(eff_named, 20)







# ============================================================
# FAMIGLIA 1 — Scatter della dicotomia broker vs produttore
# ============================================================
install.packages("ggplot2")   # salta se già installato
library(ggplot2)

# Lavoriamo sui club-stagione con estrazione positiva (gli "estrattori")
plotdf <- model_df[model_df$Y_margin_sum > 0, ]

# Comprimo Y con asinh per la leggibilità (non fa dominare i 3 outlier giganti)
plotdf$Y_compressed <- asinh(plotdf$Y_margin_sum)

ggplot(plotdf, aes(x = betweenness, y = Y_compressed)) +
  geom_point(alpha = 0.4, color = "steelblue") +
  geom_smooth(method = "lm", se = TRUE, color = "darkred") +
  labs(
    title = "Due vie all'estrazione di valore?",
    subtitle = "Ogni punto = club-stagione con Y > 0",
    x = "Betweenness (posizione strutturale)",
    y = "Estrazione di valore (asinh di Y)"
  ) +
  theme_minimal()




##-------- BROKER vs. PRODUTTORI
library(ggplot2)

plotdf <- model_df[model_df$Y_margin_sum > 0, ]
plotdf$Y_compressed <- asinh(plotdf$Y_margin_sum)
plotdf$log_bet <- log1p(plotdf$betweenness)
# efficienza: quanto estrae per euro speso (i produttori-vivaio sono altissimi qui)
plotdf$efficiency <- plotdf$Y_margin_sum / (plotdf$spend_sum + 1e6)
# cappo l'efficienza al 95° percentile per non far dominare i casi estremi al colore
cap <- quantile(plotdf$efficiency, 0.95)
plotdf$eff_capped <- pmin(plotdf$efficiency, cap)

ggplot(plotdf, aes(x = log_bet, y = Y_compressed, color = eff_capped)) +
  geom_point(alpha = 0.7, size = 2) +
  scale_color_gradient(low = "grey70", high = "red", name = "Efficienza\n(Y/spesa)") +
  labs(
    title = "Broker vs produttori: due vie all'estrazione di valore",
    subtitle = "Rosso = estrae molto spendendo poco (produttore/vivaio)",
    x = "Betweenness (log, posizione strutturale)",
    y = "Estrazione di valore (asinh di Y)"
  ) +
  theme_minimal()







# I club a betweenness bassa sono PIÙ o MENO efficienti degli altri?
model_df$efficiency <- model_df$Y_margin_sum / (model_df$spend_sum + 1e6)
pos <- model_df[model_df$Y_margin_sum > 0, ]

# Dividi in due gruppi: periferici (betweenness sotto mediana) vs centrali (sopra)
pos$gruppo <- ifelse(pos$betweenness <= median(pos$betweenness), "periferici", "centrali")

aggregate(cbind(efficiency, Y_margin_sum, spend_sum, betweenness) ~ gruppo,
          data = pos, FUN = median)

cat("\nEfficienza mediana per gruppo:\n")
tapply(pos$efficiency, pos$gruppo, median)










library(ggplot2)

pos$gruppo <- ifelse(pos$betweenness <= median(pos$betweenness),
                     "Periferici\n(bassa betweenness)", "Centrali\n(alta betweenness)")

# Efficienza cappata per leggibilità (i pochi estremi schiaccerebbero le scatole)
cap <- quantile(pos$efficiency, 0.95)
pos$eff_plot <- pmin(pos$efficiency, cap)

ggplot(pos, aes(x = gruppo, y = eff_plot, fill = gruppo)) +
  geom_boxplot(alpha = 0.7, outlier.alpha = 0.3) +
  scale_fill_manual(values = c("grey60", "tomato")) +
  labs(
    title = "I club periferici estraggono valore più efficientemente",
    subtitle = "Efficienza = valore estratto per euro speso (cappata al 95° pct)",
    x = NULL, y = "Efficienza (Y / spesa)"
  ) +
  theme_minimal() +
  theme(legend.position = "none")





# Cerchiamo gli id dei selling club noti (i nomi devono matchare quelli in 'names')
cerca <- c("Benfica", "Porto", "Ajax", "Lille", "Sporting", "Salzburg",
           "Atalanta", "Udinese", "Monaco", "Sevilla", "Dortmund", "PSV",
           "Athletic", "Real Madrid", "Barcelona", "Manchester City", "Chelsea")

for (nome in cerca) {
  hit <- names[grepl(nome, names$club_name, ignore.case = TRUE), ]
  if (nrow(hit) > 0) {
    for (i in 1:nrow(hit)) cat(hit$club_id[i], "->", hit$club_name[i], "\n")
  }
}







#--------- Grafico posizione selling club
install.packages("ggrepel")   # salta se già installato
library(ggplot2); library(ggrepel)

pos <- model_df[model_df$Y_margin_sum > 0, ]
pos$efficiency <- pos$Y_margin_sum / (pos$spend_sum + 1e6)
pos$log_bet <- log1p(pos$betweenness)

# id dei club da etichettare
selling <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
rich    <- c(418,131,281,631)

pos$tipo <- "altri"
pos$tipo[pos$club_id %in% selling] <- "selling club"
pos$tipo[pos$club_id %in% rich]    <- "club ricco"

# etichetta: nome del club (solo per i protagonisti), cappo efficienza per leggibilità
pos <- merge(pos, names, by = "club_id", all.x = TRUE)
pos$eff_plot <- pmin(pos$efficiency, quantile(pos$efficiency, 0.97))
pos$lab <- ifelse(pos$tipo != "altri", pos$club_name, NA)

ggplot(pos, aes(x = log_bet, y = eff_plot)) +
  geom_point(data = subset(pos, tipo=="altri"), color="grey80", alpha=0.5, size=1.5) +
  geom_point(data = subset(pos, tipo!="altri"), aes(color=tipo), size=3) +
  geom_text_repel(aes(label=lab), size=3, max.overlaps=20) +
  scale_color_manual(values=c("selling club"="tomato","club ricco"="steelblue")) +
  labs(title="Dove si posizionano i selling club",
       subtitle="Efficienza (Y/spesa) vs posizione strutturale (betweenness log)",
       x="Betweenness (log)", y="Efficienza (Y / spesa, cappata)", color=NULL) +
  theme_minimal()



#------ grafico mediato posizione selling club


library(ggplot2); library(ggrepel); library(dplyr)

pos <- model_df[model_df$Y_margin_sum > 0, ]
pos$efficiency <- pos$Y_margin_sum / (pos$spend_sum + 1e6)

# AGGREGA per club: un punto per club (mediana delle sue stagioni)
agg <- pos %>%
  group_by(club_id) %>%
  summarise(betweenness = median(betweenness),
            efficiency  = median(efficiency),
            n_stagioni  = n()) %>%
  filter(n_stagioni >= 2)          # solo club con almeno 2 stagioni (più stabili)

agg <- merge(agg, names, by="club_id", all.x=TRUE)
agg$log_bet <- log1p(agg$betweenness)

selling <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
rich    <- c(418,131,281,631)
agg$tipo <- "altri"
agg$tipo[agg$club_id %in% selling] <- "selling club"
agg$tipo[agg$club_id %in% rich]    <- "club ricco"
agg$lab <- ifelse(agg$tipo!="altri", agg$club_name, NA)
agg$eff_plot <- pmin(agg$efficiency, quantile(agg$efficiency, 0.97))

ggplot(agg, aes(x=log_bet, y=eff_plot)) +
  geom_point(data=subset(agg,tipo=="altri"), color="grey82", alpha=0.6, size=2) +
  geom_point(data=subset(agg,tipo!="altri"), aes(color=tipo), size=3.5) +
  geom_text_repel(aes(label=lab), size=3.2, max.overlaps=15, fontface="bold") +
  scale_color_manual(values=c("selling club"="tomato","club ricco"="steelblue")) +
  labs(title="Due vie all'estrazione di valore",
       subtitle="Un punto per club (mediana delle stagioni). In alto = estrae molto spendendo poco.",
       x="Betweenness (log) — posizione strutturale",
       y="Efficienza (valore estratto / spesa)", color=NULL) +
  theme_minimal() + theme(legend.position="bottom")







# I periferici efficienti estraggono valore VERO o è solo denominatore piccolo?
pos <- model_df[model_df$Y_margin_sum > 0, ]
pos$efficiency <- pos$Y_margin_sum / (pos$spend_sum + 1e6)
pos$gruppo <- ifelse(pos$betweenness <= median(pos$betweenness), "periferici", "centrali")

# Per i due gruppi: efficienza, ma anche VALORE ASSOLUTO estratto e spesa
aggregate(cbind(Y_margin_sum, spend_sum, efficiency) ~ gruppo,
          data = pos, FUN = median)

# Domanda chiave: tra i periferici ad alta efficienza (top 25%),
# quanto valore assoluto estraggono davvero?
peri <- pos[pos$gruppo == "periferici", ]
soglia <- quantile(peri$efficiency, 0.75)
peri_eff <- peri[peri$efficiency >= soglia, ]
cat("\nPeriferici ad alta efficienza (top 25%):\n")
cat("  Valore assoluto estratto (mediana):", median(peri_eff$Y_margin_sum), "\n")
cat("  Spesa (mediana):", median(peri_eff$spend_sum), "\n")
cat("  N. casi:", nrow(peri_eff), "\n")








# ============================================================
# VISUALIZZARE LA RETE — stagione 2018 (scelta casuale)
# ============================================================
library(igraph)

e2018 <- edges[edges$season == 2018, ]
g <- graph_from_data_frame(e2018[, c("source","target","total_value")], directed = TRUE)

# Attacca i nomi ai nodi (invece degli id)
idx <- match(as.integer(V(g)$name), names$club_id)
V(g)$label <- names$club_name[idx]

# Dimensione nodo = betweenness (i broker diventano grandi)
bt <- betweenness(as.undirected(g, mode="collapse"), weights = NA)
V(g)$size <- 3 + 8 * (bt / max(bt))

# Colore: rosso per i selling club noti, grigio per gli altri
selling <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
V(g)$color <- ifelse(as.integer(V(g)$name) %in% selling, "tomato", "grey75")

# Mostra l'etichetta solo per i nodi importanti (betweenness alta) per non affollare
V(g)$label <- ifelse(bt >= quantile(bt, 0.85), V(g)$label, NA)

set.seed(42)
plot(g,
     layout = layout_with_fr(g),        # force-directed: i club connessi si avvicinano
     edge.arrow.size = 0.2,
     edge.width = 0.5,
     edge.color = "grey85",
     vertex.frame.color = NA,
     vertex.label.cex = 0.7,
     vertex.label.color = "black",
     main = "Rete dei trasferimenti — stagione 2018")






# scelta di quali stagione rappresentare
# Quanti archi (densità) ha ogni stagione? Le più ricche sono le più belle da mostrare.
library(dplyr)
densita <- edges %>%
  group_by(season) %>%
  summarise(n_archi = n(),
            n_club  = n_distinct(c(source, target)),
            valore_tot = sum(total_value)) %>%
  arrange(desc(n_archi))
print(densita)



# scelta: 2011 - 2015 - 2019
install.packages("tidygraph")
library(igraph); library(ggraph); library(tidygraph); library(dplyr)



# ============================================================
# PANNELLO RETI — 2011, 2015, 2019 (stile coerente)
# ============================================================


selling   <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
rich      <- c(418,131,281,631)
label_ids <- c(720,294,610,16,800)   # Porto, Benfica, Ajax, Dortmund, Atalanta

plot_rete <- function(anno) {
  e <- edges[edges$season == anno, ]
  g <- graph_from_data_frame(e[, c("source","target","total_value")], directed = TRUE)
  bt  <- betweenness(as.undirected(g, mode="collapse"), weights = NA)
  ids <- as.integer(V(g)$name)
  
  V(g)$bt    <- bt
  V(g)$ruolo <- ifelse(ids %in% selling, "selling club",
                       ifelse(ids %in% rich, "club ricco", "altri"))
  V(g)$lab   <- ifelse(ids %in% label_ids,
                       names$club_name[match(ids, names$club_id)], NA)
  
  set.seed(42)
  ggraph(as_tbl_graph(g), layout = "fr") +
    geom_edge_link(aes(width = total_value), alpha = 0.15, color = "grey40") +
    geom_node_point(aes(size = bt, color = ruolo)) +
    geom_node_text(aes(label = lab), size = 3.2, fontface = "bold",
                   repel = TRUE, na.rm = TRUE) +
    scale_color_manual(values = c("selling club"="tomato",
                                  "club ricco"="steelblue", "altri"="grey75")) +
    scale_edge_width(range = c(0.2, 2.5), guide = "none") +
    scale_size(range = c(1, 10), guide = "none") +
    labs(title = paste("Rete dei trasferimenti —", anno),
         subtitle = "Nodi ~ betweenness · rosso = selling club · blu = club ricco",
         color = NULL) +
    theme_graph() + theme(legend.position = "bottom")
}

# Genera e salva i tre plot ad alta risoluzione
for (anno in c(2011, 2015, 2019)) {
  p <- plot_rete(anno)
  ggsave(paste0("rete_", anno, ".png"), p, width = 9, height = 8, dpi = 300, bg = "white")
  print(p)   # mostra anche a schermo
}
cat("Salvati: rete_2011.png, rete_2015.png, rete_2019.png\n")








# ============================================================
# VENTAGLIO — PageRank sul grafo INVERTITO (cattura i produttori)
# ============================================================
library(igraph)

stagioni <- sort(unique(edges$season))
pr_list <- list()

for (s in stagioni) {
  es <- edges[edges$season == s, ]
  # Grafo INVERTITO: arco acquirente -> venditore
  # (così il PageRank premia chi VENDE a club importanti)
  g_inv <- graph_from_data_frame(
    data.frame(from = es$target, to = es$source),  # <-- invertiti
    directed = TRUE
  )
  pr <- page_rank(g_inv)$vector
  pr_list[[as.character(s)]] <- data.frame(
    club_id = as.integer(names(pr)),
    season  = s,
    pagerank = as.numeric(pr)
  )
}
pr_df <- do.call(rbind, pr_list)

# Aggancia il PageRank alla tabella misure esistente
measures <- merge(measures, pr_df, by = c("club_id","season"), all.x = TRUE)
measures$pagerank[is.na(measures$pagerank)] <- 0

# Chi ha PageRank alto? Devono emergere i produttori di talento di qualità
top_pr <- measures[order(-measures$pagerank), ]
top_pr <- merge(top_pr, names, by="club_id", all.x=TRUE)
cat("=== Top 15 PageRank invertito (vende a club importanti) ===\n")
head(top_pr[order(-top_pr$pagerank), c("club_name","season","pagerank","betweenness")], 15)






# ============================================================
# VENTAGLIO — indice SORGENTE-POZZO (produttore vs accumulatore)
# ============================================================
library(igraph); library(dplyr)

stagioni <- sort(unique(edges$season))
sp_list <- list()

for (s in stagioni) {
  es <- edges[edges$season == s, ]
  
  # Valore VENDUTO da ogni club (come source) e COMPRATO (come target)
  venduto   <- es %>% group_by(club_id = source) %>% summarise(out_val = sum(total_value))
  comprato  <- es %>% group_by(club_id = target) %>% summarise(in_val  = sum(total_value))
  
  sp <- merge(venduto, comprato, by = "club_id", all = TRUE)
  sp[is.na(sp)] <- 0
  sp$season <- s
  
  # Indice sorgente-pozzo sul VALORE: >0 = venditore netto (produttore), <0 = acquirente netto
  # Normalizzato sul totale movimentato, così sta tra -1 e +1
  sp$source_sink <- (sp$out_val - sp$in_val) / (sp$out_val + sp$in_val + 1)
  
  sp_list[[as.character(s)]] <- sp[, c("club_id","season","source_sink")]
}
sp_df <- do.call(rbind, sp_list)

# Aggancia alle misure
measures <- merge(measures, sp_df, by = c("club_id","season"), all.x = TRUE)
measures$source_sink[is.na(measures$source_sink)] <- 0

# I selling club sono davvero "sorgenti" (source_sink > 0)?
selling <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
rich    <- c(418,131,281,631)
measures$tipo <- ifelse(measures$club_id %in% selling, "selling club",
                        ifelse(measures$club_id %in% rich, "club ricco", "altri"))

cat("Indice sorgente-pozzo mediano per tipo:\n")
print(aggregate(source_sink ~ tipo, data = measures, FUN = median))










# ============================================================
# MAPPA DEI RUOLI — betweenness (posizione) × sorgente-pozzo (direzione)
# ============================================================
library(ggplot2); library(ggrepel); library(dplyr)

# Aggrega per club: un punto stabile per club (almeno 3 stagioni)
mappa <- measures %>%
  group_by(club_id) %>%
  summarise(betweenness = median(betweenness),
            source_sink = median(source_sink),
            n = n()) %>%
  filter(n >= 3)

mappa <- merge(mappa, names, by="club_id", all.x=TRUE)
mappa$log_bet <- log1p(mappa$betweenness)

selling <- c(294,720,610,1082,336,409,800,410,162,368,383,621,16)
rich    <- c(418,131,281,631)
mappa$tipo <- ifelse(mappa$club_id %in% selling, "selling club",
                     ifelse(mappa$club_id %in% rich, "club ricco", "altri"))
label_ids <- c(720,294,610,16,800,621,418,131,281,631,162,368)  # i club-simbolo
mappa$lab <- ifelse(mappa$club_id %in% label_ids, mappa$club_name, NA)

# Linee divisorie: mediana della betweenness, e zero per sorgente-pozzo
x_div <- median(mappa$log_bet)

ggplot(mappa, aes(x = log_bet, y = source_sink)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = x_div, linetype = "dashed", color = "grey50") +
  geom_point(data = subset(mappa, tipo=="altri"), color="grey80", alpha=0.5, size=1.5) +
  geom_point(data = subset(mappa, tipo!="altri"), aes(color=tipo), size=3) +
  geom_text_repel(aes(label=lab), size=3, fontface="bold", max.overlaps=20) +
  scale_color_manual(values=c("selling club"="tomato","club ricco"="steelblue")) +
  annotate("text", x=max(mappa$log_bet), y=0.9, label="PRODUTTORE\n(vende netto)",
           hjust=1, size=3, color="grey40", fontface="italic") +
  annotate("text", x=max(mappa$log_bet), y=-0.9, label="ACCUMULATORE\n(compra netto)",
           hjust=1, size=3, color="grey40", fontface="italic") +
  labs(title="La mappa dei ruoli nel mercato",
       subtitle="Posizione (betweenness) × direzione del flusso (sorgente-pozzo)",
       x="Betweenness (log) →  più centrale",
       y="Sorgente-pozzo →  più venditore netto", color=NULL) +
  theme_minimal() + theme(legend.position="bottom")


# salviamolo
ggsave("mappa_ruoli.png", width = 9, height = 8, dpi = 300, bg = "white")














# ============================================================
# EDA STRUTTURALE DELLA RETE — caratterizzazione (stagione 2017)
# ============================================================
library(igraph)

e2017 <- edges[edges$season == 2017, ]
g <- graph_from_data_frame(e2017[, c("source","target","total_value")], directed = TRUE)
gu <- as.undirected(g, mode = "collapse")

cat("=== DIMENSIONI ===\n")
cat("Nodi (club):", vcount(g), "| Archi (canali):", ecount(g), "\n")

cat("\n=== GRADO ===\n")
cat("Grado medio:", round(mean(degree(g, mode="all")), 2), "\n")
cat("Grado max:", max(degree(g, mode="all")), "\n")

cat("\n=== DENSITÀ ===\n")
# quota di connessioni esistenti sul totale possibile: mercati reali sono SPARSI
cat("Densità:", round(edge_density(g), 4), "\n")

cat("\n=== CLUSTERING ===\n")
# tendenza a formare triangoli: i partner dei miei partner sono miei partner?
cat("Clustering coefficient:", round(transitivity(gu), 3), "\n")

cat("\n=== COMPONENTE GIGANTE ===\n")
comp <- components(gu)
cat("N. componenti:", comp$no, "\n")
cat("Quota nodi nella componente gigante:",
    round(max(comp$csize)/vcount(gu)*100, 1), "%\n")

cat("\n=== CAMMINI (small world?) ===\n")
gg <- induced_subgraph(gu, which(comp$membership == which.max(comp$csize)))
cat("Distanza media:", round(mean_distance(gg), 2), "\n")
cat("Diametro:", diameter(gg), "\n")


## istogramma
library(ggplot2)
gradi <- degree(g, mode = "all")

ggplot(data.frame(grado = gradi), aes(x = grado)) +
  geom_histogram(binwidth = 1, fill = "steelblue", color = "white") +
  labs(title = "Distribuzione del grado — coda pesante (scale-free)",
       subtitle = "Molti club con pochi collegamenti, pochi hub con molti",
       x = "Grado (numero di club partner)", y = "Numero di club") +
  theme_minimal()





# ============================================================
# La distribuzione del grado è una POWER LAW? Test visivo log-log
# ============================================================
library(igraph); library(ggplot2); library(dplyr)

# Aggrega i gradi su TUTTE le stagioni (più dati nella coda = test più affidabile)
gradi_all <- c()
for (s in sort(unique(edges$season))) {
  es <- edges[edges$season == s, ]
  g  <- graph_from_data_frame(es[, c("source","target")], directed = FALSE)
  gradi_all <- c(gradi_all, degree(g))
}
gradi_all <- gradi_all[gradi_all > 0]

# --- CCDF: P(grado >= k), il metodo corretto per la coda ---
tab <- as.data.frame(table(gradi_all))
tab$grado <- as.numeric(as.character(tab$gradi_all))
tab <- tab[order(tab$grado), ]
tab$ccdf <- rev(cumsum(rev(tab$Freq))) / sum(tab$Freq)

ggplot(tab, aes(x = grado, y = ccdf)) +
  geom_point(size = 2.5, color = "steelblue") +
  scale_x_log10() + scale_y_log10() +
  labs(title = "Distribuzione del grado in scala log-log (CCDF)",
       subtitle = "Se è una power law, i punti seguono una retta",
       x = "Grado k (log)", y = "P(grado ≥ k)  (log)") +
  theme_minimal()



