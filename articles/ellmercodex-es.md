# Primeros pasos con ellmercodex

> *English version:*
> [`vignette("ellmercodex", package = "ellmercodex")`](https://simxnherrera.github.io/ellmercodex/articles/ellmercodex.md).

`ellmercodex` te permite usar tu plan de ChatGPT desde R como un
proveedor de [`ellmer`](https://ellmer.tidyverse.org/). Inicias sesión
una vez con tu cuenta de ChatGPT y
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
te da un objeto `Chat` de `ellmer` común y corriente: sin clave de API y
sin el CLI de Codex.

Usa el flujo documentado por OpenAI [“Sign in with
ChatGPT”](https://developers.openai.com/siwc/token-sharing-open-source)
para apps de código abierto que se ejecutan localmente, y la API pública
de Responses. El uso del plan de ChatGPT es una vista previa de OpenAI,
y `ellmercodex` no está afiliado a OpenAI ni cuenta con su respaldo.

Los ejemplos de este artículo necesitan una sesión iniciada, así que no
se ejecutan al construirlo. Las salidas que se muestran provienen de una
sesión real.

## Comprueba tu instalación

``` r

library(ellmercodex)

codex_available()
#> [1] TRUE
```

[`codex_available()`](https://simxnherrera.github.io/ellmercodex/reference/codex_available.md)
comprueba que estén instaladas las dependencias y la versión de `ellmer`
soportada. No lee tus credenciales ni se conecta a la red, así que
`TRUE` no garantiza que una solicitud vaya a funcionar.

## Inicia sesión

``` r

codex_login()
```

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
abre tu navegador, donde eliges una cuenta y un espacio de trabajo de
ChatGPT y autorizas el uso del plan. La credencial se guarda de forma
privada y se renueva sola, así que solo necesitas hacerlo una vez por
equipo.
[`vignette("authentication-es")`](https://simxnherrera.github.io/ellmercodex/articles/authentication-es.md)
explica dónde se guarda y cómo cerrar sesión o cambiar de cuenta.

## Tu primer chat

``` r

chat <- chat_codex(model = "gpt-6-luna", effort = "low")
chat$chat("Hola desde R")
#> ¡Hola! ¿En qué puedo ayudarte con R?
```

Cada llamada a `$chat()` se suma al historial de la conversación, así
que las preguntas siguientes tienen el contexto anterior. Usa
`$stream()` para ver la respuesta a medida que se genera:

``` r

chat$stream("Dame tres ideas para nombrar un paquete de R.")
```

Si no indicas `model`,
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
elige un modelo utilizable del catálogo de tu cuenta.
[`vignette("models-es")`](https://simxnherrera.github.io/ellmercodex/articles/models-es.md)
explica cómo listar los modelos, elegir uno y fijar el esfuerzo de
razonamiento.

## Es un Chat de ellmer

[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
devuelve un `Chat` de `ellmer` normal, así que la documentación de
`ellmer` se aplica. Esto funciona igual que con cualquier otro
proveedor:

- **Datos estructurados** con `$chat_structured()`: consulta el artículo
  de `ellmer` sobre [datos
  estructurados](https://ellmer.tidyverse.org/articles/structured-data.html)
  (en inglés).
- **Llamadas a herramientas** con `$register_tool()`: consulta
  [tool/function
  calling](https://ellmer.tidyverse.org/articles/tool-calling.html) (en
  inglés).
- **Streaming y asincronía** con `$stream()`, `$chat_async()` y
  `$stream_async()`, incluida la cancelación con
  [`ellmer::stream_controller()`](https://ellmer.tidyverse.org/reference/stream_controller.html):
  consulta [streaming and async
  APIs](https://ellmer.tidyverse.org/articles/streaming-async.html) (en
  inglés).
- **Imágenes y PDF** con
  [`ellmer::content_image_file()`](https://ellmer.tidyverse.org/reference/content_image_url.html),
  [`ellmer::content_pdf_file()`](https://ellmer.tidyverse.org/reference/content_pdf_file.html)
  y funciones similares.
- **Clonado e historial** con `$clone()`, `$get_turns()` y
  `$set_turns()`: consulta [programming with
  ellmer](https://ellmer.tidyverse.org/articles/programming.html) (en
  inglés).

[`vignette("text-analysis-es")`](https://simxnherrera.github.io/ellmercodex/articles/text-analysis-es.md)
combina datos estructurados y herramientas en una tarea real de análisis
de texto.

Algunas cosas son distintas por cómo funciona el uso del plan de
ChatGPT: `parallel_chat()` y `batch_chat()` no están soportadas, y se
rechazan argumentos como `temperature` y `max_tokens`.
[`vignette("errors-and-limits-es")`](https://simxnherrera.github.io/ellmercodex/articles/errors-and-limits-es.md)
los enumera y muestra cómo manejar los errores.

## Más información

- [`vignette("authentication-es")`](https://simxnherrera.github.io/ellmercodex/articles/authentication-es.md):
  inicio de sesión, credenciales guardadas y cierre de sesión.
- [`vignette("models-es")`](https://simxnherrera.github.io/ellmercodex/articles/models-es.md):
  modelos y esfuerzo de razonamiento.
- [`vignette("text-analysis-es")`](https://simxnherrera.github.io/ellmercodex/articles/text-analysis-es.md):
  datos estructurados y herramientas sobre texto real.
- [`vignette("errors-and-limits-es")`](https://simxnherrera.github.io/ellmercodex/articles/errors-and-limits-es.md):
  clases de condición, límites del plan y lo que no está soportado.

## Cómo citar

Para citar `ellmercodex` en publicaciones, use:

Herrera, S. (2026). *ellmercodex: ‘ChatGPT’ Plan Provider for ‘ellmer’*.
R package version 0.2.0,
<https://doi.org/10.32614/CRAN.package.ellmercodex>

``` bibtex
@Manual{ellmercodex,
  title = {{ellmercodex}: 'ChatGPT' Plan Provider for 'ellmer'},
  author = {Simon Herrera},
  year = {2026},
  note = {R package version 0.2.0},
  doi = {10.32614/CRAN.package.ellmercodex},
  url = {https://CRAN.R-project.org/package=ellmercodex},
}
```
