import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string pluginId: "io.github.brm-src.omawatch"
  readonly property bool isSpanish: uiLanguage === "es"
  readonly property int cardWidth: Math.min(Style.space(700), panel.width - Style.gapsOut * 2)
  property bool opened: false
  property bool busy: false
  property int requestId: 0
  property int requestToken: 0
  property var callback: null
  property bool backdropReady: false
  property string uiLanguage: Qt.locale().name.toLowerCase().startsWith("es") ? "es" : "en"
  property string phase: "home"        // home, quiz, letterboxd, syncing, results
  property int quizIndex: 0
  property var answers: ({})
  property var films: []
  property string status: ""
  property string username: ""
  property string syncToken: ""
  property string watchlistToken: ""
  property var syncProgress: ({})
  property string syncError: ""
  property bool usingWatchlist: false

  function words(es, en) { return root.isSpanish ? es : en }

  readonly property var quiz: [
    {
      key: "state",
      titleEs: "¿Cómo llegas a la sesión?",
      titleEn: "How are you arriving tonight?",
      options: [
        { value: "drained", es: "Sin batería", en: "Drained" },
        { value: "restless", es: "Inquieto, quiero acción", en: "Restless, I want action" },
        { value: "pensive", es: "Pensativo, algo para masticar", en: "Pensive, something to chew on" },
        { value: "good", es: "Bien, dispuesto a todo", en: "Good, open to anything" }
      ]
    },
    {
      key: "appetite",
      titleEs: "¿Qué te apetece?",
      titleEn: "What's the appetite?",
      options: [
        { value: "comfort", es: "Confort, algo tibio", en: "Comfort, something warm" },
        { value: "feel-deep", es: "Sentir hondo", en: "Feel deeply" },
        { value: "horror", es: "Terror", en: "Horror" },
        { value: "weird", es: "Algo raro", en: "Something weird" },
        { value: "transformative", es: "Algo que me cambie", en: "Something transformative" }
      ]
    },
    {
      key: "runtime",
      titleEs: "¿Cuánto tiempo tienes?",
      titleEn: "How much time do you have?",
      options: [
        { value: "short", es: "Corto, menos de 100 minutos", en: "Short, under 100 minutes" },
        { value: "medium", es: "Medio, entre 100 y 130", en: "Medium, 100 to 130" },
        { value: "long", es: "Largo, sin apuro", en: "Long, no rush" }
      ]
    },
    {
      key: "tone",
      titleEs: "¿Qué tono?",
      titleEn: "Which tone?",
      options: [
        { value: "dark", es: "Oscuro", en: "Dark" },
        { value: "light", es: "Luminoso", en: "Light" }
      ]
    },
    {
      key: "depth",
      titleEs: "¿Cómo quieres salir de la sesión?",
      titleEn: "How do you want to leave the session?",
      options: [
        { value: "fun", es: "Entretenido", en: "Entertained" },
        { value: "warm", es: "Abrazado", en: "Hugged" },
        { value: "thoughtful", es: "Pensando", en: "Thinking" },
        { value: "uneasy", es: "Inquieto", en: "Uneasy" },
        { value: "ruined", es: "Destrozado", en: "Wrecked" }
      ]
    }
  ]

  readonly property var currentQuestion: root.quiz[Math.min(root.quizIndex, root.quiz.length - 1)]

  function errorText(payload) {
    switch (payload.error) {
      case "network": return root.words("No hay conexión con el servicio. Intenta de nuevo.", "No connection to the service. Try again.")
      case "invalid-username": return root.words("Ese usuario no parece válido.", "That username doesn't look valid.")
      case "user_not_found": return root.words("No encontré esa cuenta. ¿Es pública la watchlist?", "Account not found. Is the watchlist public?")
      case "sync-token-missing":
      case "watchlist-token-missing": return root.words("La sincronización expiró. Vuelve a cargarla.", "The sync expired. Load it again.")
      case "sync-status-unavailable":
      case "sync-unavailable": return root.words("No pude sincronizar la watchlist ahora.", "I couldn't sync the watchlist right now.")
      case "no-picks": return root.words("No encontré películas con esa combinación. Prueba otro ánimo.", "No films matched that combination. Try another mood.")
      case "recommend-unavailable":
      case "surprise-unavailable": return root.words("El servicio no respondió. Intenta de nuevo.", "The service didn't respond. Try again.")
      default: return root.words("Algo falló. Intenta de nuevo.", "Something failed. Try again.")
    }
  }

  function resetQuiz() {
    root.quizIndex = 0
    root.answers = ({})
  }

  function open() {
    root.opened = true
    root.backdropReady = false
    backdropGuard.restart()
  }

  function close() {
    root.opened = false
    root.backdropReady = false
    backdropGuard.stop()
    root.busy = false
    root.callback = null
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function runHelper(command, payload, done) {
    root.busy = true
    root.requestId = root.requestId + 1
    root.requestToken = root.requestId
    var myToken = root.requestId
    root.callback = function(response) {
      if (root.requestToken !== myToken) return
      done(response)
    }
    helper.inputText = JSON.stringify(payload)
    helper.command = ["python3", root.helperPath, command]
    helper.running = true
  }

  readonly property string helperPath: Qt.resolvedUrl("omawatch.py").toString().replace("file://", "")

  function handlePayload(raw) {
    root.busy = false
    var payload
    try { payload = JSON.parse(String(raw || "{}")) }
    catch (error) {
      root.status = root.words("No pude leer la respuesta.", "I couldn't read the response.")
      return
    }
    if (root.callback) root.callback(payload)
    root.callback = null
  }

  function pickFilm(film, index) {
    if (!film) return ""
    var bits = []
    if (film.title) bits.push(String(film.title))
    if (film.year) bits.push(String(film.year))
    if (film.director) bits.push(String(film.director))
    if (film.runtime) bits.push(String(film.runtime) + " min")
    return bits.join(" · ")
  }

  function genreLine(film) {
    var genres = (film && film.genres) || []
    if (!genres.length) return ""
    return genres.slice(0, 3).join(" · ")
  }

  function overviewLine(film) {
    var text = String((film && film.overview) || "")
    if (!text) return ""
    return text.length > 220 ? text.slice(0, 220).trim() + "…" : text
  }

  function safeHttpUrl(value) {
    var url = String(value || "").trim()
    return /^https:\/\/[a-z0-9.-]+/i.test(url) ? url : ""
  }

  function openFilmLink(film, field) {
    var url = root.safeHttpUrl(film ? film[field] : "")
    if (url !== "") Quickshell.execDetached(["xdg-open", url])
  }

  // ---------- actions ----------

  function startQuiz(withWatchlist) {
    root.usingWatchlist = withWatchlist
    if (withWatchlist && !root.watchlistToken) {
      root.phase = "letterboxd"
      root.status = ""
      return
    }
    root.resetQuiz()
    root.phase = "quiz"
    root.status = ""
  }

  function answerQuestion(value) {
    var question = root.currentQuestion
    var next = {}
    for (var key in root.answers) next[key] = root.answers[key]
    next[question.key] = value
    root.answers = next
    if (root.quizIndex < root.quiz.length - 1) {
      root.quizIndex = root.quizIndex + 1
    } else {
      finishQuiz()
    }
  }

  function finishQuiz() {
    root.phase = "results"
    root.status = root.words("Buscando tu película…", "Looking for your film…")
    var payload = {
      lang: root.uiLanguage,
      country: "CL",
      answers: root.answers,
      seed: Math.floor(Math.random() * 1000000)
    }
    if (root.usingWatchlist) payload.watchlist_token = root.watchlistToken
    root.runHelper(root.usingWatchlist ? "recommend-wl" : "recommend", payload, function(response) {
      if (!response.ok) {
        root.films = []
        root.status = root.errorText(response)
        return
      }
      root.films = response.films || []
      root.status = root.usingWatchlist
        ? root.words("De tu watchlist de Letterboxd.", "From your Letterboxd watchlist.")
        : root.words("Elegidas para tu ánimo de hoy.", "Picked for tonight's mood.")
    })
  }

  function surpriseMe() {
    root.usingWatchlist = false
    root.phase = "results"
    root.status = root.words("Sorpréndeme…", "Surprise me…")
    var profiles = ["cozy", "dark", "weird", "uplifting"]
    var payload = {
      lang: root.uiLanguage,
      country: "CL",
      profile: profiles[Math.floor(Math.random() * profiles.length)],
      seed: Math.floor(Math.random() * 1000000)
    }
    root.runHelper("surprise", payload, function(response) {
      if (!response.ok) {
        root.films = []
        root.status = root.errorText(response)
        return
      }
      root.films = response.films || []
      root.status = root.words("Una apuesta del azar.", "A random wager.")
    })
  }

  function startSync() {
    var name = root.username.trim().toLowerCase()
    if (name === "") {
      root.syncError = root.words("Escribe tu usuario de Letterboxd.", "Type your Letterboxd username.")
      return
    }
    root.syncError = ""
    root.phase = "syncing"
    root.syncProgress = ({})
    root.runHelper("sync-start", { username: name }, function(response) {
      if (!response.ok) {
        root.phase = "letterboxd"
        root.syncError = root.errorText(response)
        return
      }
      root.syncToken = response.sync_token || ""
      // Cached watchlist: the sync response already carries the token.
      if (response.watchlist_token) {
        root.watchlistToken = response.watchlist_token
        root.phase = "quiz"
        root.resetQuiz()
        root.status = root.words("Watchlist lista. Responde y te elijo de ahí.", "Watchlist ready. Answer and I'll pick from it.")
        return
      }
      pollTimer.interval = Math.max(1000, response.next_poll_after_ms || 3000)
      pollTimer.restart()
    })
  }

  function pollSync() {
    if (!root.syncToken) return
    root.runHelper("sync-status", { sync_token: root.syncToken }, function(response) {
      if (!response.ok) {
        pollTimer.stop()
        root.phase = "letterboxd"
        root.syncError = root.errorText(response)
        return
      }
      root.syncProgress = response.progress || ({})
      if (response.status === "ready" || response.status === "ready_partial") {
        pollTimer.stop()
        root.watchlistToken = response.watchlist_token || ""
        root.phase = "quiz"
        root.resetQuiz()
        root.status = root.words("Watchlist lista. Responde y te elijo de ahí.", "Watchlist ready. Answer and I'll pick from it.")
        return
      }
      if (response.status === "failed") {
        pollTimer.stop()
        root.phase = "letterboxd"
        root.syncError = root.errorText({ error: response.error || "sync-unavailable" })
        return
      }
      pollTimer.interval = Math.max(1000, response.next_poll_after_ms || 3000)
      pollTimer.restart()
    })
  }

  function disconnectLetterboxd() {
    root.watchlistToken = ""
    root.syncToken = ""
    root.username = ""
    root.usingWatchlist = false
    root.phase = "home"
    root.status = root.words("Watchlist desconectada.", "Watchlist disconnected.")
  }

  IpcHandler {
    target: root.pluginId
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function show(): string { root.open(); return "ok" }
    function hide(): string { root.close(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function home(): string { root.open(); root.phase = "home"; root.status = ""; return "ok" }
    function quiz(): string { root.open(); root.startQuiz(false); return "ok" }
    function letterboxd(): string { root.open(); root.phase = "letterboxd"; return "ok" }
    function surprise(): string { root.open(); root.surpriseMe(); return "ok" }
  }

  Process {
    id: helper
    property string inputText: ""
    stdinEnabled: true
    onStarted: {
      write(inputText + "\u001e")
      inputText = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handlePayload(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.busy) {
        root.busy = false
        root.status = root.words("No pude completar eso.", "I couldn't complete that.")
      }
    }
  }

  Timer {
    id: backdropGuard
    interval: 200
    repeat: false
    onTriggered: root.backdropReady = true
  }

  Timer {
    id: pollTimer
    interval: 3000
    repeat: false
    onTriggered: root.pollSync()
  }

  PanelWindow {
    id: panel
    screen: Quickshell.screens[0]
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: root.pluginId
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_W && (event.modifiers & Qt.MetaModifier)) {
          root.close()
          event.accepted = true
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      MouseArea {
        anchors.fill: parent
        enabled: root.backdropReady
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(Style.space(640), parent.height - Style.bar.sizeHorizontal - Style.gapsOut * 3)
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.bar.sizeHorizontal + Style.gapsOut
      anchors.rightMargin: Style.gapsOut
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      scale: 1
      opacity: 1
      Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      onVisibleChanged: { if (visible) { scale = 0.97; opacity = 0; Qt.callLater(function() { scale = 1; opacity = 1 }) } }

      MouseArea { anchors.fill: parent }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ---- header ----
        Row {
          width: parent.width
          height: titleColumn.implicitHeight

          Column {
            id: titleColumn
            width: parent.width - closeButton.width - Style.spacing.md
            spacing: Style.spacing.xs
            Text {
              textFormat: Text.PlainText
              text: root.words("omawatch", "omawatch")
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.phase === "quiz"
                ? root.words("Pregunta " + (root.quizIndex + 1) + " de " + root.quiz.length, "Question " + (root.quizIndex + 1) + " of " + root.quiz.length)
                : root.phase === "results"
                  ? root.words("Para hoy", "For tonight")
                  : root.words("Qué ver hoy, según tu ánimo", "What to watch tonight, by mood")
              color: Color.menu.text
              opacity: 0.62
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
          }

          Button {
            id: closeButton
            anchors.verticalCenter: parent.verticalCenter
            text: "×"
            fontSize: Style.font.iconLarge
            tooltipText: root.words("Cerrar (Esc)", "Close (Esc)")
            onClicked: root.close()
          }
        }

        // ---- status line ----
        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.status !== ""
          text: root.status
          color: Color.menu.text
          opacity: 0.62
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---- progress ----
        Item {
          id: progressBar
          width: parent.width
          height: Style.space(5)
          visible: root.busy
          clip: true

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Color.menu.text
            opacity: 0.14
          }
          Rectangle {
            id: progressIndicator
            width: Math.max(Style.space(72), parent.width * 0.28)
            height: parent.height
            radius: height / 2
            color: Color.accent
            x: -width

            SequentialAnimation on x {
              running: root.busy
              loops: Animation.Infinite
              NumberAnimation { from: -progressIndicator.width; to: progressBar.width; duration: 900; easing.type: Easing.InOutQuad }
              PauseAnimation { duration: 120 }
            }
          }
        }

        // ---- content ----
        Flickable {
          id: content
          width: parent.width
          height: Math.max(80, parent.height - y - footerRow.height - Style.spacing.md * 2)
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: contentColumn
            width: content.width
            spacing: Style.spacing.md

            // HOME
            Column {
              width: parent.width
              visible: root.phase === "home"
              spacing: Style.spacing.md

              Button {
                width: parent.width
                selected: true
                active: !root.busy
                text: root.words("test de ánimo rápido", "quick mood test")
                tooltipText: root.words("Cinco preguntas y te recomiendo una película.", "Five questions and I recommend a film.")
                onClicked: root.startQuiz(false)
              }

              Button {
                width: parent.width
                active: !root.busy
                visible: root.watchlistToken === ""
                text: root.words("usar mi watchlist de letterboxd", "use my letterboxd watchlist")
                tooltipText: root.words("Conecta tu cuenta y elige de tu propia lista.", "Connect your account and pick from your own list.")
                onClicked: { root.phase = "letterboxd"; root.status = "" }
              }

              Column {
                width: parent.width
                visible: root.watchlistToken !== ""
                spacing: Style.spacing.sm

                Button {
                  width: parent.width
                  selected: true
                  active: !root.busy
                  text: root.words("elegir de mi watchlist", "pick from my watchlist")
                  tooltipText: root.words("Test de ánimo + tu watchlist de Letterboxd.", "Mood test + your Letterboxd watchlist.")
                  onClicked: root.startQuiz(true)
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.words("Conectado como @" + root.username, "Connected as @" + root.username)
                  color: Color.menu.text
                  opacity: 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }

                Button {
                  text: root.words("desconectar", "disconnect")
                  active: !root.busy
                  onClicked: root.disconnectLetterboxd()
                }
              }

              Button {
                width: parent.width
                active: !root.busy
                text: root.words("sorpréndeme", "surprise me")
                tooltipText: root.words("Sin preguntas, una apuesta del azar.", "No questions, a random wager.")
                onClicked: root.surpriseMe()
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.words("No guardamos nada: el usuario solo sirve para leer tu watchlist pública.", "Nothing is stored: the username is only used to read your public watchlist.")
                color: Color.menu.text
                opacity: 0.45
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }

            // QUIZ
            Column {
              width: parent.width
              visible: root.phase === "quiz"
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.currentQuestion ? (root.isSpanish ? root.currentQuestion.titleEs : root.currentQuestion.titleEn) : ""
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.Wrap
              }

              Repeater {
                model: root.currentQuestion ? root.currentQuestion.options : []

                delegate: Button {
                  width: parent.width
                  active: !root.busy
                  text: root.isSpanish ? modelData.es : modelData.en
                  onClicked: root.answerQuestion(modelData.value)
                }
              }

              Row {
                width: parent.width
                spacing: Style.spacing.md

                Button {
                  visible: root.quizIndex > 0
                  text: root.words("← atrás", "← back")
                  active: !root.busy
                  onClicked: { root.quizIndex = root.quizIndex - 1 }
                }

                Item { width: Math.max(0, parent.width - backBtn.width - skipBtn.width - parent.spacing * 2); height: 1 }

                Button {
                  id: skipBtn
                  text: root.words("saltar", "skip")
                  active: !root.busy
                  onClicked: root.answerQuestion("")
                }
              }
              Button { id: backBtn; visible: false }
            }

            // LETTERBOXD
            Column {
              width: parent.width
              visible: root.phase === "letterboxd"
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.words("Tu usuario de Letterboxd", "Your Letterboxd username")
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              TextField {
                id: userField
                width: parent.width
                placeholderText: root.words("ej: callmeout", "e.g. callmeout")
                text: root.username
                onTextChanged: { root.username = text }
                onAccepted: root.startSync()
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                background: BorderSurface {
                  radius: Style.cornerRadius
                  color: Style.controlFill(false, false, Color.menu.text, Color.accent)
                  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: root.syncError !== ""
                text: root.syncError
                color: Color.accent
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }

              Button {
                width: parent.width
                selected: true
                active: !root.busy
                text: root.words("cargar watchlist", "load watchlist")
                onClicked: root.startSync()
              }

              Button {
                text: root.words("volver", "back")
                active: !root.busy
                onClicked: { root.phase = "home" }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.words("Solo se lee la watchlist pública. Nada se guarda.", "Only the public watchlist is read. Nothing is stored.")
                color: Color.menu.text
                opacity: 0.45
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
              }
            }

            // SYNCING
            Column {
              width: parent.width
              visible: root.phase === "syncing"
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.words("Leyendo tu watchlist…", "Reading your watchlist…")
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: (root.syncProgress.slugs_total || 0) > 0
                text: (root.syncProgress.slugs_resolved || 0) + " / " + (root.syncProgress.slugs_total || 0)
                color: Color.menu.text
                opacity: 0.62
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // RESULTS
            Column {
              width: parent.width
              visible: root.phase === "results"
              spacing: Style.spacing.md

              ListView {
                id: resultsList
                width: parent.width
                height: Math.max(0, root.films.length * Style.space(166) + Math.max(0, root.films.length - 1) * Style.spacing.md)
                model: root.films
                spacing: Style.spacing.md
                interactive: false
                clip: false

                delegate: BorderSurface {
                  width: resultsList.width
                  radius: Style.cornerRadius
                  color: index === 0 ? Style.controlFill(false, false, Color.menu.text, Color.accent) : Color.menu.background
                  borderSpec: index === 0
                    ? Border.controlSpec("accent", Color.menu.text, Color.accent)
                    : Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
                  padding: Style.spacing.controlPaddingX
                  height: Style.space(166)
                  visible: true

                  Row {
                    id: filmRow
                    width: parent.width - parent.contentLeftInset - parent.contentRightInset
                    height: parent.height - parent.contentTopInset - parent.contentBottomInset
                    spacing: Style.spacing.md

                    Image {
                      id: poster
                      width: Style.space(84)
                      height: Style.space(126)
                      source: modelData.poster || ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      visible: modelData.poster !== undefined && modelData.poster !== null && modelData.poster !== ""

                      Rectangle {
                        anchors.fill: parent
                        color: Color.menu.text
                        opacity: 0.08
                        visible: poster.status !== Image.Ready
                      }
                    }

                    Column {
                      width: parent.width - (poster.visible ? poster.width + parent.spacing : 0)
                      spacing: Style.spacing.xs

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.pickFilm(modelData, index)
                        color: index === 0 ? Color.accent : Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.bold: index === 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        visible: root.genreLine(modelData) !== ""
                        text: root.genreLine(modelData)
                        color: Color.menu.text
                        opacity: 0.62
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        visible: root.overviewLine(modelData) !== ""
                        text: root.overviewLine(modelData)
                        color: Color.menu.text
                        opacity: 0.72
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                      }

                      Row {
                        spacing: Style.spacing.md

                        Button {
                          visible: root.safeHttpUrl(modelData.tmdb) !== ""
                          text: root.words("dónde verla ↗", "where to watch ↗")
                          active: !root.busy
                          onClicked: root.openFilmLink(modelData, "justwatch")
                        }

                        Button {
                          visible: root.safeHttpUrl(modelData.letterboxd) !== ""
                          text: "letterboxd ↗"
                          active: !root.busy
                          onClicked: root.openFilmLink(modelData, "letterboxd")
                        }
                      }
                    }
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.spacing.md

                Button {
                  width: parent.width
                  text: root.words("← otro ánimo", "← another mood")
                  active: !root.busy
                  onClicked: { root.resetQuiz(); root.phase = "quiz" }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.md

                  Item { width: Math.max(0, parent.width - againBtn.width - homeBtn.width - parent.spacing); height: 1 }

                  Button {
                    id: againBtn
                    text: root.words("otra ronda", "another round")
                    active: !root.busy
                    onClicked: root.finishQuiz()
                  }

                  Button {
                    id: homeBtn
                    text: root.words("inicio", "home")
                    active: !root.busy
                    onClicked: { root.phase = "home" }
                  }
                }
              }
            }
          }
        }

        // ---- footer ----
        Row {
          id: footerRow
          width: parent.width
          spacing: Style.spacing.md

          Item {
            width: Math.max(0, parent.width - poweredBy.width - parent.spacing)
            height: 1
          }

          Item {
            id: poweredBy
            width: Style.space(190)
            height: parent.height

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "powered by: mood-watch.app"
              color: Color.menu.text
              opacity: 0.62
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["xdg-open", "https://mood-watch.app"])
            }
          }
        }
      }
    }
  }
}
