# Dependencias internas de ellmer (preparación para CRAN)

Inventario de todo lo que `ellmercodex` toma de `ellmer` fuera de su API
exportada, medido contra ellmer 0.5.0. Todas las referencias son a
`R/ellmer-compatibility.R` salvo que se indique otra cosa.

`R CMD check --as-cran` no lo marca (usa `utils::getFromNamespace()` y no
`:::`), pero un revisor humano de CRAN sí lo ve, y el patrón de desbloquear
bindings de un objeto R6 ajeno es el más probable de generar un rechazo.

## Resumen

| Grupo | Qué es | Nº de símbolos | Gravedad CRAN | ¿Se elimina localmente? |
|---|---|---:|---|---|
| A | Extender `Provider` (lo que la documentación de ellmer pide) | 19 | Media | Parcialmente |
| B | Reemplazar métodos privados de `Chat` | 22 + 4 métodos privados | Alta | No, requiere cambio upstream |
| C | `getFromNamespace()` sobre el propio paquete | 4 | Ninguna | Sí, cosmético |

## Grupo A: implementar un Provider

La ayuda de `?ellmer::Provider` dice: *"subclass `Provider` ... and then
implement the various generics"*, pero ninguno de esos generics está exportado.
Es la parte más defendible ante CRAN y la más fácil de pedir upstream.

### A1. Clase padre

| Símbolo | Línea | Uso | Alternativa local |
|---|---|---|---|
| `ProviderOpenAI` | 19 | Padre de `CodexProvider` para heredar `chat_body` de Responses API | `S7::S7_class(ellmer::chat_openai(...)$get_provider())` evita `getFromNamespace` pero sigue dependiendo de una clase no exportada: cosmético. Real: heredar de `ellmer::Provider` y escribir el cuerpo Responses propio (grande). |

### A2. Generics S7 en los que se registran métodos (`codex_register_ellmer_provider_methods()`, l. 998-1035)

`chat_body` (también se llama al método padre, l. 144, leyendo la tabla interna
`attr(generic, "methods")`), `chat_request`, `stream_parse`, `stream_content`,
`stream_merge_chunks`, `value_turn`, `value_tokens`, `value_finish_reason`,
`has_batch_support`, `count_tokens`, `file_upload`, `file_list`, `file_get`,
`file_download`, `file_delete`.

Sin alternativa local: `S7::method<-` necesita el objeto generic. Pedir que
ellmer los exporte.

### A3. Helpers

| Símbolo | Línea | Uso | Alternativa local |
|---|---|---|---|
| `base_request` | 178 | Request base con credenciales y headers | Reescribir con `httr2::request()` + `req_auth_bearer_token()` (~10 líneas) |
| `chat_path` | 179 | Sufijo `/responses` | Constante local |
| `modify_list` | 180 | Merge de `extra_args` | `utils::modifyList()` |
| `ContentJson` | 735 | Turno de salida estructurada | Ninguna: es la clase que `chat_structured()` espera. Pedir export. |
| `dollars` | 958, 964 | Formatear costo | Devolver `NA_real_` o formatear localmente |
| `get_token_cost` | 960 | Costo por tokens | Devolver `NA` (la suscripción no tiene precio por token) |

## Grupo B: reemplazar la ejecución privada de `Chat`

`codex_install_private_submit_methods()` (l. 1102-1199) accede a
`chat$.__enclos_env__$private`, inspecciona el cuerpo y los argumentos de
métodos privados, **desbloquea bindings** con `rlang::env_binding_unlock()` y
reemplaza `chat_impl`, `chat_impl_async`, `submit_turns` y
`submit_turns_async`.

### Por qué existe

En ellmer, `Chat$submit_turns()` en modo no-stream (`$chat(echo = "none")`,
`$chat_structured()`, etc.) llama `chat_perform(mode = "value")`, que hace
`httr2::req_perform()` y luego `resp_body_json()`. El endpoint de Codex solo
responde por SSE, así que ese camino no puede funcionar, y `chat_perform` no es
un generic: el Provider no puede interceptarlo.

### Lo que la reimplementación necesita de ellmer

`TurnAccumulator`, `chat_perform`, `stream_content`, `stream_merge_chunks`,
`emitter`, `cat_line`, `content_text`, `echo_non_text_contents`,
`otel_chat_input`, `local_chat_otel_span`, `local_agent_otel_span`,
`record_chat_otel_span_status`, `record_chat_otel_span_output`,
`turn_has_tool_request`, `is_tool_request`, `is_tool_result`, `invoke_tools`,
`invoke_tools_async`, `new_tool_context`, `tool_results_as_turn`,
`turn_get_tool_errors`, `warn_tool_errors`.

Además, en `R/provider-codex.R` hay comprobaciones de contrato con
`asNamespace("ellmer")` (l. 70, 108) y `getFromNamespace("TurnAccumulator")` /
`"Chat"` (l. 119, 201).

### Riesgo concreto

Cualquier refactor interno de `Chat` en ellmer rompe el paquete. Cuando eso
pase en CRAN, el revdep check de ellmer falla y CRAN pide arreglarlo en dos
semanas o archiva `ellmercodex`.

### Solución

Solo upstream: si ellmer permite que un Provider declare que solo transmite por
stream (o hace de `chat_perform` un generic), en modo `"value"` ellmer
consumiría el stream y lo fusionaría con `stream_merge_chunks()` antes de
`value_turn()`. Así todo el grupo B desaparece y `ellmercodex` vuelve a usar
`Chat` sin tocarlo.

## Grupo C: el propio paquete

`codex_submit_turns_sync/async` y `codex_chat_impl_sync/async` (l. 1067, 1089,
1433, 1454) se buscan con `getFromNamespace(..., "ellmercodex")` porque los
métodos instalados cambian de entorno al del `Chat`. No es un problema de
política y desaparece junto con el grupo B.

## Estado (2026-10-06)

- Hecho: `base_request`, `chat_path`, `modify_list`, `dollars` y
  `get_token_cost` reemplazados por código local
  (`codex_provider_base_request()`, `codex_provider_error_body()`,
  `codex_dollars()`). La request propia ya no reintenta, como pide
  `docs/technical-design.md`; antes heredaba los reintentos de ellmer.
- Hecho: `skip_if_ellmer_contract_changed()` en los tests que construyen chats
  (solo actúa en CRAN) y sección en `cran-comments.md`.
- Pendiente: abrir el issue upstream y poner su URL en `cran-comments.md`
  (`<ISSUE_URL>`).

## Migración a "Sign in with ChatGPT" (rama `siwc-auth`)

La autenticación y el transporte ahora siguen el flujo documentado por OpenAI
para apps de código abierto
(<https://developers.openai.com/siwc/token-sharing-open-source>):
registro dinámico con `client_id=dynamic_agent_client`, `client_id` emitido
por usuario y espacio de trabajo, `ext_agent_host_id`, y
`POST https://api.openai.com/v1/responses`. Esto elimina el bloqueo de
términos de uso (reutilizar el `client_id` del CLI de Codex y llamar a
`chatgpt.com/backend-api/codex`), pero **no cambia el inventario de internals
de ellmer**:

- El requisito de `stream = TRUE` sigue existiendo, ahora documentado por
  OpenAI ("Must set `store: false` and `stream: true`" en las limitaciones de
  la vista previa). El grupo B sigue siendo necesario y el argumento del issue
  se refuerza: el endpoint stream-only es la API pública de Responses con un
  token de plan de ChatGPT.
- `codex_responses_body_adapt()` posprocesa la salida de `chat_body` de
  `ProviderOpenAI` (mensajes `system` a `developer`, herramientas en un
  `namespace`, campos prohibidos). No usa símbolos nuevos de ellmer.
- `codex_stream_next()` envuelve la función generadora que devuelve
  `chat_perform()` (ya listado) para mapear errores HTTP de httr2.
- `base_url` pasa a ser `https://api.openai.com/v1`, el mismo que usa
  `ProviderOpenAI`; el issue puede mencionarlo como un caso de subclase de
  `ProviderOpenAI` con credenciales dinámicas y cuerpo restringido.

## Plan propuesto

1. **Upstream (bloqueante):** abrir el issue de abajo en `tidyverse/ellmer`.
2. **Local, ya:** eliminar los helpers del grupo A3 que tienen reemplazo
   trivial (`base_request`, `chat_path`, `modify_list`, `dollars`,
   `get_token_cost`). Quedan 4 helpers menos.
3. **Local, ya:** proteger con `skip_on_cran()` los tests que verifican
   contratos privados de `Chat`, para que un cambio interno de ellmer no se
   convierta en un fallo de revdep, y documentarlo en `cran-comments.md`.
4. **Decisión:** enviar a CRAN antes o después de que ellmer resuelva el
   issue. Enviar antes con el grupo B intacto tiene alta probabilidad de
   rechazo o de archivo en el próximo release de ellmer.

## Borrador del issue para tidyverse/ellmer

> **Title:** Support third-party providers: export provider generics and allow stream-only providers
>
> `?Provider` says that to add a backend you subclass `Provider` and implement
> the generics, but those generics (`chat_body()`, `chat_request()`,
> `stream_parse()`, `stream_content()`, `stream_merge_chunks()`,
> `value_turn()`, `value_tokens()`, `value_finish_reason()`,
> `has_batch_support()`, `count_tokens()`, `file_*()`) aren't exported, so a
> package outside ellmer can only register methods through
> `getFromNamespace()`. That is hard to get past CRAN review.
>
> I maintain [ellmercodex](https://github.com/simxnherrera/ellmercodex), a
> provider that uses a ChatGPT plan through OpenAI's documented "Sign in
> with ChatGPT" flow. With that token, the public Responses API **only**
> supports `stream = TRUE` (and `store = FALSE`). In `Chat$submit_turns()`, non-streaming calls go through
> `chat_perform(mode = "value")` -> `req_perform()` -> `resp_body_json()`,
> and the provider can't intercept that because `chat_perform()` isn't a
> generic. Today I work around it by replacing `Chat`'s private
> `submit_turns()`/`chat_impl()` methods, which is fragile for both of us.
>
> Would you consider:
>
> 1. Exporting the provider generics (and `ContentJson`, needed to build
>    structured-output turns), maybe documented as "for provider authors".
> 2. A way for a provider to say it only streams, for example a
>    `provider_stream_only()` generic defaulting to `FALSE`, or making the
>    value path a generic. When it's `TRUE`, `"value"` mode would consume the
>    stream and fold it with `stream_merge_chunks()` before `value_turn()`.
>    `parallel_chat()`/`batch_chat()` could error clearly for such providers.
> 3. Optionally exporting `ProviderOpenAI` (or the Responses-API body
>    builder) for subclassing; previously discussed in #595.
>
> Happy to send a PR for (2) if the direction sounds right.
