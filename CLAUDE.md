# Quanto mi costi — regole del progetto

Sito sui prezzi in Italia con due sezioni:
- **Abbonamenti digitali**: storico in `data/history.json`, monitor in Ruby
  che rileva le variazioni (`bin/monitor`).
- **Indice Margherita**: segnalazioni degli utenti in `data/margherita.json`,
  importate dal modulo con `bin/margherita-import`.

Il sito (`site/index.html` → `bin/site` → `_site/`) è pubblicato su GitHub
Pages dal workflow `sito`. Vedi README.md.

## Regole non negoziabili

1. **Lo storico si modifica solo tramite `bin/approve`.** Vale per
   `data/history.json` e per `data/margherita.json`. Mai editarli a mano, né
   da script, né "solo per correggere un refuso". Una variazione nasce come
   file in `data/pending/` (dal monitor, dall'import o scritto a mano), si
   rivede lì e poi si approva con `bin/approve <file>`. Chiedi sempre conferma
   all'utente prima di lanciarlo.
2. **Ogni evento deve avere almeno una fonte** in `sources`: per gli
   abbonamenti un URL verificabile (comunicato ufficiale, pagina del servizio,
   articolo di stampa); per la margherita il riferimento alla risposta del
   modulo con la foto (`modulo:<id>`). Niente fonte, niente dato. I test
   `test_every_event_has_a_source_and_a_valid_date` e
   `test_approved_data_file_is_valid` lo controllano; non indebolirli.
3. **Niente IA nell'estrazione dei prezzi.** L'estrazione resta deterministica:
   regex in `config/services.yml` + `PriceMonitor::Extractor`. Non usare LLM,
   OCR "intelligente" o API di modelli per leggere, indovinare o correggere
   prezzi. Se l'estrazione fallisce, il monitor deve segnalarlo, non inventare.

4. **Indice Margherita: mai dati dalle app di delivery** (i loro termini lo
   vietano). Solo segnalazioni degli utenti e pizzerie che aderiscono.
5. **Il repo è pubblico: niente dati personali.** Le foto di menu e
   scontrini restano nel modulo; nel repo e sul sito non vanno link alle
   foto, nomi, email o altro di chi segnala. Mai dati inventati o "di
   esempio" in `data/`: sul sito sembrerebbero veri (i dati finti stanno
   solo nei test).

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
