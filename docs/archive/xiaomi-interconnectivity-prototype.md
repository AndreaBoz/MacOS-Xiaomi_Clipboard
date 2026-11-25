> Archivio del prototipo e delle prove iniziali. Non usare questo documento come guida alla configurazione corrente. Vedi il README nella radice del progetto.

# Xiaomi Clipboard — Mac ↔ HyperOS

**Modalità attuale, versione 1.2.0:** l’app cliccabile usa solo KDE Connect. Attivandola avvia KDE Connect e l’invio degli screenshot; disattivandola chiude KDE Connect e salva i nuovi screenshot sulla Scrivania. Xiaomi Interconnectivity è stato chiuso e non è più richiesto. Il vecchio normalizzatore Swift è mantenuto come strumento opzionale da terminale, ma non interviene negli appunti durante l’uso quotidiano.

Per l’invio automatico degli screenshot con il normale ⌘⇧4 tramite KDE Connect, vedi [SCREENSHOT.md](SCREENSHOT.md).

Piccola app nativa per rendere il testo copiato sul Mac compatibile con Xiaomi Interconnectivity. Swift, AppKit e framework di sistema; nessuna dipendenza esterna. Mac Apple Silicon, macOS 12 o successivo. Il binario preparato su questo Mac è arm64; il progetto può essere ricompilato anche su Intel.

## Uso quotidiano, senza Terminale

L’app **Xiaomi Clipboard.app** era generata nella cartella `dist/` del progetto (poi eventualmente copiata altrove).

Dalla versione 1.0.2 ha un’icona corallo con Mac, tablet e frecce turchesi. L’immagine originale è in `Assets/AppIcon.png`, l’icona macOS in `Assets/AppIcon.icns` e il prompt di generazione imagegen in `Assets/icon-prompt.txt`. `scripts/build-icon.sh` prepara tutte le risoluzioni usando gli strumenti macOS `sips` e `iconutil`; `package` e `install` la includono automaticamente.

1. Lascia **KDE Connect aperto sul tablet**, associato al Mac e sulla stessa rete Wi-Fi. L’app avvia automaticamente KDE Connect sul Mac.
2. Quando inizi a studiare, fai doppio clic su **Xiaomi Clipboard**. Compare «Sincronizzazione attivata»; premi **OK**. Puoi chiudere la finestra: il servizio resta attivo in background.
3. Copia normalmente da Firefox, ChatGPT o altre app. Attendi circa un secondo prima di incollare sul tablet.
4. Quando finisci, riapri la stessa app: si disattivano sia gli appunti sia l’invio automatico degli screenshot. Compare «Sincronizzazione disattivata». Premi **OK**.

Non serve tenere aperto il Terminale. Il doppio clic **inverte lo stato**, quindi se è già attiva la spegne. Se la finestra precedente è ancora aperta, chiudila con OK prima di riaprire l’app.

**Non parte da sola al prossimo accesso al Mac.** Il servizio termina anche al logout o allo spegnimento. La sospensione del Mac non termina la sessione: il servizio riprende al risveglio.

La modalità attuale KDE non riscrive gli appunti del Mac. Solo usando manualmente il vecchio normalizzatore in modalità plain, il testo elaborato perde HTML, grassetto, corsivo e RTF anche per gli incolla sul Mac. È il compromesso concordato e verificato sul tablet. Disattivare l’app non ripristina la formattazione già rimossa: per recuperarla, ricopia il testo dall’origine. L’app lascia intatti immagini, file, URL copiati come oggetti, contenuti multipli e formati non riconosciuti.

Il collegamento corrente è gestito da KDE Connect. Non serve un cavo USB o il debug Android. La chiusura di KDE Connect da parte dell’app ferma anche le eventuali altre funzioni di KDE Connect sul Mac.

## Che cosa abbiamo verificato

Prove effettuate il 10 novembre 2026 su questo Mac, macOS 26.2, Swift 6.2:

| Prova | Esito |
|---|---|
| Copia da Firefox, senza normalizzazione | Non arriva al tablet, confermato dall’utente |
| Formati della copia Firefox | Sono già presenti `public.html` e `public.utf8-plain-text` |
| Aggiornamento in place sulla copia appartenente a Firefox | `setString` restituisce `false` |
| Ripubblicazione degli stessi dati e nello stesso ordine | `changeCount` 53 → 54; il tablet non si aggiorna |
| Ripubblicazione come solo testo | `changeCount` 54 → 55; l’utente conferma che arriva sul tablet |
| Copia selezionata da ChatGPT con ⌘C, versione 1.0.1 | Arriva al tablet automaticamente; confermato dall’utente dopo l’aggiornamento |
| Suite locale su dati sintetici | 21 test superati, nessun errore, nessun test saltato |

Queste prove giustificano **plain come modalità predefinita**. Non dimostrano che Xiaomi richieda universalmente soltanto testo semplice: nella copia verificata, cambiare proprietario e contatore mantenendo l’HTML non è bastato, mentre rimuovere l’HTML ha risolto. Il comportamento interno di Xiaomi non è documentato da questi test. La modalità con UTF-8 come primo formato è disponibile ma non è stata verificata sul tablet.

Il binario è stato provato sul tablet con Firefox e, dalla versione 1.0.1, con testo selezionato in ChatGPT e copiato con ⌘C. Il pulsante Copia della risposta non è stato verificato separatamente. Resta utile una verifica quotidiana nella direzione Xiaomi → Mac.

La versione 1.0.0 escludeva la copia da ChatGPT perché conteneva i metadati `org.chromium.source-url` e `org.chromium.internal.source-rfh-token`. La versione 1.0.1 riconosce esattamente questi due identificatori di provenienza di Chromium. In modalità plain vengono eliminati insieme alla formattazione; in modalità preserve restano invariati. Il tipo `public.url` continua a indicare un URL copiato come oggetto e resta escluso. Non sono stati ammessi genericamente tutti i formati `org.chromium.*`: tipi sconosciuti, immagini, file e marker riservati continuano a bloccare l’operazione. Tre nuovi test verificano la normalizzazione automatica, la conservazione dei metadati in preserve e la precedenza delle protezioni.

## Architettura e protezioni

- Eseguibile compilato in Release; non interpreta Swift a ogni avvio.
- Un LaunchAgent della sessione grafica mantiene il servizio indipendente dalla finestra. L’app crea un plist temporaneo, lo carica e rimuove il file. Non scrive un LaunchAgent permanente per l’avvio al login.
- Polling di `changeCount` ogni 0,4 secondi, con tolleranza di 50 ms. A riposo legge solo il contatore; non rilegge continuamente il contenuto.
- Aspetta un intervallo stabile prima di intervenire: latenza normalmente di circa 0,4–0,8 secondi, più eventuali ritardi di sistema. Una copia nuova sostituisce quella ancora in attesa.
- Legge solo un singolo elemento testuale con rappresentazione UTF-8. Materializza tutti i formati ammessi prima di cancellare alcunché; se ne manca uno, rinuncia.
- Blocca formati immagine, PDF, audio/video, URL, file, RTFD con possibili allegati, dati promessi, tipi sconosciuti e marker riservati/transitori/remoti. Gli alias legacy testuali aggiunti da macOS sono riconosciuti.
- Un URL copiato **solo come stringa** è testo e può essere normalizzato; un elemento che espone `public.url` o `public.file-url` viene lasciato intatto.
- Limite complessivo dei dati materializzati: 8 MiB. Una rappresentazione va comunque letta prima che se ne possa misurare la dimensione: il limite non è un tetto assoluto al picco di memoria.
- Non elabora gli appunti preesistenti all’avvio. Dopo aver attivato il servizio, esegui una **nuova copia**.
- Ignora il proprio contatore di scrittura. Per tre secondi ignora un testo appena riscritto, anche se ricompare con formati diversi. Un limite di otto riscritture in dieci secondi fa scattare una pausa di trenta secondi. Durante la pausa lascia gli appunti invariati; dopo la pausa serve una nuova copia.
- Un lock per utente impedisce più istanze del nuovo servizio. **Ferma il vecchio script con Ctrl+C:** il prototipo non conosce questo lock.
- Nessuna cronologia o trasmissione di rete propria. Testo e rappresentazioni restano in memoria solo durante l’operazione; per pochi secondi conserva hash del testo per riconoscere gli echi. I log non contengono testo copiato.
- Su errore di scrittura tenta un recupero solo se mantiene ancora la proprietà degli appunti, poi si arresta. Un arresto gestito non innesca riavvii automatici; un crash viene riavviato da launchd con throttling.

`NSPasteboard` non offre una transazione atomica «controlla e sostituisci». Il programma verifica il contatore durante la lettura e immediatamente prima/dopo l’acquisizione della proprietà; resta una piccola finestra di concorrenza inevitabile con altre app. Non può garantire l’assenza di interferenze con qualsiasi clipboard manager o riconoscere ogni contenuto arrivato da Xiaomi se manca un marker di origine. Evita di far funzionare contemporaneamente altri normalizzatori.

Non è possibile ricostruire perfettamente la semantica di ogni provider di dati, né leggere e ripristinare tutte le opzioni private di condivisione del produttore. I marker noti vengono rispettati e i tipi sconosciuti sono esclusi. Un testo senza marker riservati non può essere riconosciuto come una password. Le protezioni si applicano al contenuto pubblicato dai produttori, non a una classificazione semantica del testo.

## Build, test e distribuzione

Per usare l’app già preparata non serve un ambiente di sviluppo. Per ricompilare bastano i Command Line Tools di Apple con Swift 5.9 o successivo:

```bash
cd /path/to/XiaomiClipboard
./clipboardctl package
./clipboardctl test
```

`package` produce `dist/Xiaomi Clipboard.app`, firmata ad hoc per uso locale. La firma non è una notarizzazione per distribuzione pubblica. Chiudi la sincronizzazione prima di sostituire o spostare la copia dell’app che usi.

La suite usa un piccolo runner Swift, senza XCTest o Xcode completo, ed esce con errore anche quando l’ambiente impedisce l’accesso alle pasteboard temporanee. I test nativi usano nomi dedicati: **non toccano gli appunti generali**. Verificano conservazione byte per byte, ordine, proprietà, conversione plain, formati protetti, elementi multipli, limiti dimensionali, corse fra copie, errori e controllo degli echi.

```bash
./clipboardctl status        # Stato anche per la sessione avviata dall’app
./clipboardctl stop          # Arresto alternativo da terminale
./clipboardctl logs          # Eventi del servizio nell’ultima ora
.build/release/xiaomi-clipboard inspect  # Solo tipi e contatori, mai il testo
```

Se macOS chiede accesso agli appunti, consentilo per l’app per permettere il monitoraggio. `inspect` mostra anche `accessBehavior` sui sistemi che lo supportano. Permessi negati o dati non disponibili fanno saltare l’operazione. Non sono richiesti permessi di Accessibilità o Registrazione schermo.

## Modalità sperimentali

Con servizio e vecchio prototipo fermi, copia un testo di prova prima di ogni comando:

```bash
.build/release/xiaomi-clipboard once --mode inplace
.build/release/xiaomi-clipboard once --mode replay
.build/release/xiaomi-clipboard once --mode preserve
.build/release/xiaomi-clipboard once --mode plain
```

| Modalità | Comportamento |
|---|---|
| `plain` | Mantiene soltanto il testo. Predefinita, verificata con il tablet |
| `preserve` | Ripubblica tutti i dati originali ammessi, mettendo UTF-8 per primo |
| `replay` | Ripubblica gli stessi dati nello stesso ordine; prova di controllo |
| `inplace` | Prova `setString` senza cancellare; può essere rifiutata sulla clipboard di un altro processo |

Nella pasteboard temporanea di proprietà del processo, `inplace` conserva HTML/RTF ma non incrementa `changeCount`. `clearContents` seguito da `writeObjects` cambia proprietario e contatore; `writeObjects` mantiene il contatore ottenuto dal clear nei test effettuati. Mettere UTF-8 per primo può influenzare applicazioni che scelgono il primo formato, anche se i byte degli altri formati sono conservati.

## Avvio automatico al login — solo opzionale

La soluzione cliccabile non lo abilita. Se in futuro preferisci tenerla sempre attiva, ferma la sessione dall’app e usa:

```bash
./clipboardctl install              # Installa e avvia in modalità plain
./clipboardctl stop                 # Ferma e disabilita anche l’avvio al login
./clipboardctl start                # Riabilita e avvia
./clipboardctl restart
./clipboardctl uninstall
```

L’installazione opzionale usa `~/Library/Application Support/XiaomiClipboard/Xiaomi Clipboard.app` e `~/Library/LaunchAgents/it.andrea.xiaomi-clipboard.plist`, senza sudo. Non è stata eseguita automaticamente. Per variare la configurazione: `./clipboardctl install preserve 0.6` (sperimentale).

Non combinare l’installazione al login con la modalità manuale di studio: condividono lo stesso servizio e la presenza del plist permanente può farlo ripartire al login. Per tornare alla sola app cliccabile, esegui `uninstall`, poi usa la copia nella cartella del progetto.

Per rimuovere la sola app cliccabile, disattivala e trascinala nel Cestino. Non lascia un agente di avvio permanente; sorgenti e build rimangono nel progetto.

## Riferimenti tecnici

API e comportamento di base: [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard), [changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount), [NSPasteboardItem](https://developer.apple.com/documentation/appkit/nspasteboarditem), header AppKit dell’SDK locale. Avvio per utente: [Apple — Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html). Convenzioni dei marker: [NSPasteboard.org](https://nspasteboard.org/).

Metadati di provenienza Chromium: [scrittura del token del frame e dell’URL sorgente](https://chromium.googlesource.com/chromium/src/+/HEAD/content/public/browser/clipboard_types.cc) e [identificatori macOS della clipboard](https://chromium.googlesource.com/chromium/src/+/main/ui/base/clipboard/clipboard_constants_mac.mm).
