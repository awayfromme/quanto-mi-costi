# Quanto mi costi — regole del progetto

Storico dei prezzi degli abbonamenti digitali in Italia (`data/history.json`)
e monitor in Ruby che rileva le variazioni (`bin/monitor`). Vedi README.md.

## Regole non negoziabili

1. **Lo storico si modifica solo tramite `bin/approve`.** Mai editare a mano
   `data/history.json`, né da script, né "solo per correggere un refuso".
   Una variazione nasce come file in `data/pending/` (dal monitor o scritto a
   mano), si rivede lì (fonti, nota, `existing_from`) e poi si approva con
   `bin/approve <file>`. Chiedi sempre conferma all'utente prima di lanciarlo.
2. **Ogni evento deve avere almeno una fonte** in `sources`: URL verificabile
   (comunicato ufficiale, pagina del servizio, articolo di stampa). Niente
   fonte, niente evento. Il test `test_every_event_has_a_source_and_a_valid_date`
   lo controlla; non indebolirlo.
3. **Niente IA nell'estrazione dei prezzi.** L'estrazione resta deterministica:
   regex in `config/services.yml` + `PriceMonitor::Extractor`. Non usare LLM,
   OCR "intelligente" o API di modelli per leggere, indovinare o correggere
   prezzi. Se l'estrazione fallisce, il monitor deve segnalarlo, non inventare.

## Come lavorare

- Test: `bundle exec rake test` (nessun browser). Devono passare prima di ogni commit.
- Giro reale: `bundle exec ruby bin/monitor <servizio>`. Serve Chrome e un **IP
  italiano**, altrimenti i prezzi non sono quelli in euro del listino italiano.
- Se il monitor propone una variazione strana (es. un calo), prima guarda
  `data/snapshots/<servizio>/latest.txt`: spesso è un prezzo promozionale o
  una riga fuori contesto, e va corretta la regex, non lo storico.
- Si monitora il **listino**, non le offerte (prova gratuita, vincoli di 6
  mesi, "a partire da"). Preferisci le pagine d'aiuto ufficiali alle landing.
- Quando cambi URL o regex in `config/services.yml`, aggiorna la fixture
  `test/fixtures/<servizio>_reale.txt` con il testo vero della pagina.
- Chiedi conferma all'utente prima di fare commit.
