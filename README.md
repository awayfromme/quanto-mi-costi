# Quanto mi costi

Storico dei prezzi degli abbonamenti digitali in Italia, con un monitor che
si accorge da solo dei rincari.

## Cosa c'è

| Percorso | Cosa fa |
|---|---|
| `data/history.json` | Lo storico: Netflix dal 2015, Spotify dal 2013, Disney+ dal 2020. Ogni variazione ha data e fonti. |
| `config/services.yml` | Quali pagine leggere e come riconoscere i piani nel testo. |
| `bin/monitor` | Giro giornaliero: legge le pagine, salva il testo, propone le variazioni. |
| `bin/approve` | Sposta una variazione proposta dentro lo storico (revisione umana). |
| `bin/report` | Listino attuale, rincari dal lancio, calcolatore "quanto paghi in più". |

## Come funziona

1. `bin/monitor` apre ogni pagina con Chrome headless (Ferrum) e prende il
   **testo visibile**, non l'HTML: un restyling delle classi CSS non rompe nulla.
2. Salva il testo in `data/snapshots/<servizio>/latest.txt`. In git, il diff di
   quel file è la prova di cosa è cambiato e quando (git scraping).
3. L'estrazione è deterministica: regex sul nome del piano + primo prezzo in
   euro nelle righe successive, con un intervallo plausibile per piano.
   Se qualcosa non torna, ti avvisa invece di inventare un numero.
4. Una variazione non va mai direttamente nello storico: finisce in
   `data/pending/` e ti arriva su Telegram. Controlli, aggiungi fonti o la
   data per i già abbonati, poi `bin/approve`.

## Avvio

```sh
bundle install
bundle exec rake test                     # 19 test, nessun browser necessario
bin/report
bin/report --since 2019-01-01 netflix:standard spotify:premium
bin/monitor --from-file netflix test/fixtures/netflix.txt   # prova a secco
bin/monitor                               # giro vero: serve Chrome e un IP italiano
```

Per le notifiche: `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID`.

## Da sapere prima di andare in produzione

- **IP italiano obbligatorio.** I prezzi cambiano per paese; i runner GitHub
  sono negli USA. Il workflow in `.github/workflows/monitor.yml` gira su un
  runner self-hosted con etichetta `italy`.
- **Verifica gli URL** in `config/services.yml` da browser italiano: le pagine
  prezzi cambiano spesso e alcune (DAZN, offerte) sono dietro login o promo.
- **Nuovi abbonati vs già abbonati**: lo storico registra la data per i nuovi
  (`date`) e, quando nota, quella per i già abbonati (`existing_from`).
  Il monitor vede solo la prima: la seconda arriva da email e notizie.

## Punti dello storico ancora da confermare

- Spotify Student dal 2025: quasi tutte le fonti dicono 6,49 €, una 6,99 €.
- Spotify Unlimited: data di dismissione non trovata; il piano è escluso dal
  listino attuale ma non ha un evento di chiusura.
- Disney+ Premium annuale 159,90 € (2025): una sola fonte di comparazione.
- Le date `existing_from` del 2025 sono il primo giorno del mese indicato
  dalle fonti, non il giorno esatto.
