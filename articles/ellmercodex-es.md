# Introducción a ellmercodex (en español)

> *English version:*
> [README](https://simxnherrera.github.io/ellmercodex/).

`ellmercodex` te permite usar una cuenta de ChatGPT desde R a través de
una interfaz de chat de [`ellmer`](https://ellmer.tidyverse.org/): los
modelos incluidos en tu plan de ChatGPT funcionan como un proveedor más
de `ellmer`, sin clave de API. Así puedes incorporar modelos de lenguaje
a tus flujos de análisis en R.

El paquete es independiente de OpenAI y no requiere una clave de API ni
el CLI de Codex. Usa el flujo documentado por OpenAI [“Sign in with
ChatGPT”](https://developers.openai.com/siwc/token-sharing-open-source)
para apps de código abierto que se ejecutan localmente, y la API pública
de Responses.

Los ejemplos de esta viñeta necesitan una sesión iniciada, así que no se
ejecutan al construirla. Las salidas que se muestran provienen de una
sesión real.

## Inicio rápido

Comprueba la integración local, inicia sesión y crea una conversación:

``` r

library(ellmercodex)

codex_available()
auth <- codex_login()

chat <- chat_codex(model = "gpt-6-luna", effort = "low")
chat$chat("Hola desde R")
#> ¡Hola! ¿En qué puedo ayudarte con R?
```

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
abre una ventana del navegador para autenticarte con tu cuenta de
ChatGPT. Como
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
devuelve un objeto `Chat` de `ellmer`, puedes usar buena parte de su
interfaz habitual. Cada llamada a `$chat()` mantiene el historial de la
conversación; usa `$stream()` si quieres recibir la respuesta en
streaming:

``` r

chat$stream("Dame tres ideas para nombrar un paquete de R.")
```

Si ya iniciaste sesión y la credencial está disponible, puedes llamar a
[`chat_codex()`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md)
directamente. Con `model = NULL`, el paquete selecciona un modelo
utilizable del catálogo de tu cuenta autenticada.

## No es solo un chatbot

Como trabajamos con un objeto `Chat` de `ellmer`, podemos pedir
resultados estructurados en lugar de texto libre. Por ejemplo, podemos
clasificar un fragmento de un debate parlamentario sobre la regulación
del cannabis:

``` r

# Fragmento real de un debate parlamentario sobre regulación del cannabis
fragmento <- paste(
  "seguimos pensando que además de la represión y del combate al",
  "narcotráfico que debe seguir con firmeza y decisión como sociedad",
  "debemos apostar a dos o tres pilares fundamentales la educación",
  "la prevención y la rehabilitación"
)

resultado <- chat$chat_structured(
  paste(
    "Clasifica el fragmento como PREVENTIVA, PUNITIVA, MIXTA o",
    "SIN_ORIENTACIÓN_ATRIBUIBLE.",
    "Usa MIXTA cuando se defiendan simultáneamente respuestas",
    "preventivas y punitivas.",
    "\n\nFragmento:",
    fragmento
  ),
  type = ellmer::type_object(
    codigo = ellmer::type_enum(c(
      "PREVENTIVA",
      "PUNITIVA",
      "MIXTA",
      "SIN_ORIENTACIÓN_ATRIBUIBLE"
    )),
    justificacion = ellmer::type_string()
  )
)

resultado
#> $codigo
#> [1] "MIXTA"
#>
#> $justificacion
#> [1] "El fragmento defiende explícitamente la represión y el combate al
#> narcotráfico, que son respuestas punitivas, y simultáneamente propone la
#> educación, la prevención y la rehabilitación, de carácter preventivo o
#> rehabilitador."
```

Para tareas de análisis de texto, esto permite solicitar directamente
una estructura que R pueda incorporar a un `data.frame`, validar o
analizar.

## Un agente dentro de R

También puedes registrar funciones como herramientas que el modelo puede
decidir utilizar durante una conversación. Supongamos que tenemos
intervenciones parlamentarias ya clasificadas:

``` r

intervenciones <- data.frame(
  partido = c("FA", "FA", "PN", "PN", "PN"),
  orientacion = c("PREVENTIVA", "MIXTA", "PUNITIVA", "PUNITIVA", "MIXTA")
)
```

Podemos crear una función de R que resuma las orientaciones observadas
para un partido y exponerla al modelo como una herramienta de `ellmer`.
La función devuelve JSON, que es lo que `ellmer` espera de una
herramienta:

``` r

resumir_partido <- function(partido_buscado) {
  intervenciones |>
    dplyr::filter(partido == partido_buscado) |>
    dplyr::count(orientacion) |>
    jsonlite::toJSON()
}

resumen_tool <- ellmer::tool(
  resumir_partido,
  name = "resumir_partido",
  description = "Cuenta las orientaciones discursivas de un partido.",
  arguments = list(partido_buscado = ellmer::type_string())
)

chat$register_tool(resumen_tool)

chat$chat(
  paste(
    "Compara las orientaciones discursivas de FA y PN.",
    "Usa la herramienta disponible."
  )
)
#> FA presenta una orientación **mixta** y una **preventiva** (una observación
#> de cada tipo). PN presenta una orientación **mixta** y dos **punitivas**.
#> En común, ambos tienen una orientación mixta; la diferencia es que FA
#> incluye una preventiva, mientras que PN se inclina más hacia lo punitivo.
```

El modelo puede decidir llamar a `resumir_partido()` para cada partido,
recibir los resultados producidos por R y utilizarlos para elaborar su
respuesta. La herramienta podría consultar una base de datos, buscar en
un corpus, realizar un cálculo, recuperar información de una API o
ejecutar cualquier otra operación que decidas implementar.

R sigue siendo quien ejecuta las funciones: el modelo solo puede
utilizar las herramientas que registres explícitamente y decide cuándo
usarlas y con qué argumentos. Como en `ellmer`, `$chat_structured()` no
usa las herramientas registradas: reúne primero el contexto con
`$chat()` y después extrae el resultado con `$chat_structured()`.

## Elegir un modelo

La disponibilidad de modelos depende de tu cuenta y espacio de trabajo.
Consulta el catálogo después de iniciar sesión:

``` r

modelos <- codex_models()
modelos[c("id", "display_name", "default_reasoning_effort",
          "supported_reasoning_efforts")]
```

El catálogo no siempre incluye todos los modelos que acepta el servicio.
Puedes pasar explícitamente un ID aunque no aparezca en
[`codex_models()`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md),
y el servicio validará el modelo y el esfuerzo. Por ejemplo,
`gpt-6-luna` funciona aunque el catálogo no lo liste.

Puedes elegir el esfuerzo de razonamiento directamente o con los
parámetros de `ellmer`:

``` r

chat <- chat_codex(model = "gpt-6-luna", effort = "max")

chat <- chat_codex(
  model = "gpt-6-luna",
  params = ellmer::params(reasoning_effort = "max")
)
```

Usa `ELLMERCODEX_MODEL` si quieres establecer un modelo sin pasarlo cada
vez:

``` r

Sys.setenv(ELLMERCODEX_MODEL = "gpt-6-luna")
chat <- chat_codex()
```

## Chat asíncrono, cancelación y archivos

El objeto `Chat` también admite los métodos asíncronos de `ellmer`:

``` r

chat$chat_async("Resume la conversación.")

controller <- ellmer::stream_controller()
stream <- chat$stream_async(
  "Escribe un cuento breve.",
  stream = "content",
  controller = controller
)
# Pasa `stream` a un consumidor asíncrono, como un componente de chat de Shiny.
# Llama a `controller$cancel()` desde la interfaz para detener la generación.
```

También puedes enviar imágenes y PDF con las funciones habituales de
`ellmer`:

``` r

chat$chat(
  ellmer::content_image_file("grafico.png"),
  ellmer::content_pdf_file("informe.pdf"),
  "Explica estos archivos."
)
```

## Autenticación

[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md)
abre el navegador para que elijas tu cuenta y espacio de trabajo de
ChatGPT y autorices el uso de tu plan. La primera vez se crea un
registro vinculado a esa cuenta; los inicios de sesión siguientes lo
reutilizan. La credencial se guarda en
`tools::R_user_dir("ellmercodex", "config")` (o en `ELLMERCODEX_HOME`)
con permisos solo para tu usuario.

Consulta el estado de inicio de sesión con un resumen de cuenta
redactado:

``` r

codex_account()
```

Para una sesión que solo dure lo que dure el proceso de R, usa:

``` r

auth <- codex_login(persist = FALSE)
```

[`codex_logout()`](https://simxnherrera.github.io/ellmercodex/reference/codex_logout.md)
cierra la sesión, revoca el token y elimina la credencial administrada
por este paquete. Para cambiar de cuenta o de espacio de trabajo, cierra
sesión y vuelve a llamar a
[`codex_login()`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md).

## Limitaciones

El uso del plan de ChatGPT mediante “Sign in with ChatGPT” es una
función en vista previa de OpenAI: requiere un plan y un espacio de
trabajo elegibles, y sus límites y funciones admitidas pueden cambiar.
Mientras dure la vista previa no se admiten `temperature`, `top_p`,
`max_tokens` ni otros argumentos que OpenAI excluye; el paquete los
rechaza antes de enviar la solicitud.

El alcance soportado es el uso interactivo de una sola conversación
mediante el objeto `Chat` público de `ellmer` 0.5.0 o posterior. El
conteo de tokens del proveedor, la gestión de archivos y las funciones
`parallel_chat*()` y `batch_chat*()` no están soportados.

`ellmercodex` es una integración independiente y no está afiliada a
OpenAI ni cuenta con su respaldo.

## Más información

- La viñeta [Primeros
  pasos](https://simxnherrera.github.io/ellmercodex/articles/getting-started-es.md)
  recorre la autenticación, los chats, las herramientas, los resultados
  estructurados y el manejo de errores.
- El [diseño
  técnico](https://github.com/simxnherrera/ellmercodex/blob/main/docs/technical-design.md)
  (en inglés) documenta la arquitectura, el ciclo de vida de las
  credenciales, el límite de transporte, la taxonomía de errores y los
  riesgos de publicación.
- El [inventario de compatibilidad con
  `ellmer`](https://github.com/simxnherrera/ellmercodex/blob/main/docs/ellmer-chat-interface.md)
  (en inglés) registra los métodos de `Chat` soportados, sus firmas, los
  valores que devuelven y las transiciones de estado.
- **Experimental:** para conservar credenciales en tu propia app en tu
  propia VM, consulta la [guía para una VM Linux de un solo
  proceso](https://github.com/simxnherrera/ellmercodex/blob/main/docs/hosted-oauth.md)
  (en inglés). Las apps que atienden a otras personas necesitan primero
  la aprobación de OpenAI.
- En R, usa
  [`?chat_codex`](https://simxnherrera.github.io/ellmercodex/reference/chat_codex.md),
  [`?codex_login`](https://simxnherrera.github.io/ellmercodex/reference/codex_login.md),
  [`?codex_models`](https://simxnherrera.github.io/ellmercodex/reference/codex_models.md)
  y `?ellmercodex-conditions` para consultar la referencia de funciones
  (en inglés).
