# omawatch

[English](README.md)

![vista previa de omawatch](preview.png)

![icono de omawatch](icon.png)

## Pantallazos reales

Son capturas del plugin funcionando en un escritorio Omarchy, no mockups:

- [inicio](screenshots/01-home-final.png) — test de ánimo, Letterboxd y sorpresa.
- [test](screenshots/02-quiz-final.png) — flujo de cinco preguntas.
- [Letterboxd](screenshots/03-letterboxd-final.png) — conexión con watchlist pública.
- [resultados](screenshots/04-results-final.png) — tres recomendaciones reales de mood-watch.app.
- [barra del escritorio](screenshots/05-desktop-bar.png) — contexto real de la barra con el icono de película.

El pequeño icono de carrete en `icon.svg` también se usa en la barra.

Panel bilingüe de Omarchy / Quickshell que elige una película para hoy. Responde un test de ánimo de cinco preguntas — o conecta tu usuario de Letterboxd y recibe recomendaciones de tu propia watchlist. Impulsado por [mood-watch.app](https://mood-watch.app).

No es un tracker ni un feed social. Responde una sola pregunta: ¿qué veo hoy?

## Qué hace

- **Test de ánimo rápido** — cinco preguntas (energía, antojo, tiempo, tono, regusto) y devuelve tres películas con póster, año, director, duración y sinopsis.
- **Watchlist de Letterboxd** — escribe tu usuario una vez, lee tu watchlist pública, y el mismo test elige de *tu* lista.
- **Sorpréndeme** — sin preguntas, una apuesta del azar.
- Cada película incluye enlaces para verla y a Letterboxd.
- Interfaz bilingüe (español/inglés) según el idioma del sistema.
- El usuario solo se usa para leer tu watchlist pública. Nada se guarda en disco y no se crea ninguna cuenta.

## Instalar

```bash
omarchy plugin add https://github.com/brm-src/omawatch.git --enable --yes
```

No requiere privilegios de administrador. El plugin necesita Omarchy/Hyprland, Quickshell, Python 3 y conexión a internet.

## Uso

1. Clic en el icono ◐ de la barra.
2. Elige **test de ánimo rápido**, **usar mi watchlist de letterboxd** o **sorpréndeme**.
3. Para Letterboxd: escribe tu usuario, espera la sincronización y responde el test.
4. Lee las tres películas y abre "dónde verla ↗" o Letterboxd si alguna te llama.

Cierra con `Escape`, `Super + W` o clic fuera de la tarjeta.

## Cómo funciona

1. `Omawatch.qml` renderiza el panel y el test, siguiendo el sistema de diseño de Omarchy (mismas fuentes, colores, bordes y espaciados que los paneles nativos).
2. `omawatch.py` es un helper sin estado: cada acción es un subprocess que consulta la API pública de mood-watch por HTTPS.
3. Las respuestas del test se mapean a los mismos ejes de puntaje que la web (energía, riesgo, tono, confianza, profundidad, duración, compañía).
4. La sincronización usa el flujo público: iniciar, consultar hasta estar lista, y pedir recomendaciones restringidas a la watchlist con el token entregado. El token vive solo en memoria.

## Privacidad

- Ningún texto, usuario ni watchlist se escribe en disco.
- Solo se lee la watchlist pública de Letterboxd; sin login, sin contraseñas, sin claves de API.
- Las consultas van a `moodwatch-api.brmcl.workers.dev` (Cloudflare). Revisa las [notas de privacidad de mood-watch](https://mood-watch.app).

## Quitar el plugin

```bash
omarchy plugin remove io.github.brm-src.omawatch --yes
```

O primero deshabilitarlo:

```bash
omarchy plugin disable io.github.brm-src.omawatch
```

## Comprobaciones de desarrollo

Ejecuta desde la raíz del repositorio:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile omawatch.py
qmllint -I /usr/share/omarchy/shell BarButton.qml Omawatch.qml
omarchy plugin validate .
```

## Licencia

MIT. Consulta [LICENSE](LICENSE).
