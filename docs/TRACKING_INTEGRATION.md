# Integração do rastreamento em páginas externas

O rastreador é independente da página monitorada. A página somente envia eventos
para a Edge Function `tracking-events`; nenhum banco, componente ou código do
site precisa ser incorporado ao OpenBSP.

## 1. Configure um projeto

Crie um projeto autenticado pela função `tracking-management` informando:

- a organização do OpenBSP;
- um nome e um `slug`;
- as origens HTTPS autorizadas, por exemplo `https://pagina.exemplo`;
- opcionalmente uma URL de destino padrão.

A resposta contém `public_key`. Essa chave identifica a instalação no navegador
e não é um segredo. A API ainda valida o header `Origin` em todas as gravações.

## 2. Instale o coletor

Troque `SEU_PROJECT_KEY` e a URL do projeto Supabase no exemplo abaixo. O
fragmento `#obsp=...`, quando presente, associa a visita a um link rastreável e
é removido imediatamente do endereço visível.

```html
<script type="module">
const endpoint = "https://SEU-PROJETO.supabase.co/functions/v1/tracking-events";
const projectKey = "SEU_PROJECT_KEY";
const params = new URLSearchParams(location.hash.slice(1));
let sessionToken = params.get("obsp") ||
  sessionStorage.getItem("openbsp_tracking_session");

if (params.has("obsp")) {
  history.replaceState(null, "", location.pathname + location.search);
}

async function track(eventName, eventType = "custom", options = {}) {
  const event = {
    event_id: crypto.randomUUID(),
    event_name: eventName,
    event_type: eventType,
    occurred_at: new Date().toISOString(),
    page_path: location.pathname,
    element_id: options.elementId,
    metadata: options.metadata,
  };

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      schema_version: "1",
      ...(sessionToken
        ? { session_token: sessionToken }
        : { project_key: projectKey }),
      events: [event],
    }),
    keepalive: true,
  });

  const result = await response.json();
  if (result.session_token) {
    sessionToken = result.session_token;
    sessionStorage.setItem("openbsp_tracking_session", sessionToken);
  }
}

await track("page_view", "page_view");

document.addEventListener("click", (event) => {
  const element = event.target.closest("[data-openbsp-event]");
  if (!element) return;
  void track(element.dataset.openbspEvent, "click", {
    elementId: element.id || undefined,
  });
});

window.openbspTrack = track;
</script>
```

Marque botões sem acoplar o rastreador ao layout:

```html
<button id="inscrever" data-openbsp-event="registration.clicked">
  Quero me inscrever
</button>
```

Eventos de formulário ou conversão podem ser enviados diretamente:

```js
await window.openbspTrack("registration.completed", "conversion", {
  metadata: { variant: "hero-a" },
});
```

Não envie nome, telefone, e-mail, CPF, tokens ou conteúdo de formulário em
`metadata`. O backend também descarta chaves e valores com aparência de dados
pessoais.

## 3. Links de mensagens

Crie um token opaco aleatório de 32 bytes no seu cliente administrativo,
preserve-o junto da `idempotency_key` para qualquer retry e envie ambos em
`POST /tracking-management/links`. O backend armazena somente o hash do token. A
resposta contém uma URL como:

```text
https://SEU-PROJETO.supabase.co/functions/v1/tracking-redirect/r/TOKEN_OPACO
```

Use essa URL no botão ou corpo da mensagem. O redirecionamento registra a
abertura, cria uma sessão curta para navegadores humanos e encaminha para a URL
HTTPS já autorizada no projeto. `message_id` é opcional, mas deve ser informado
quando se deseja relacionar os eventos à conversa do OpenBSP.

Não gere um novo `tracking_token` ao repetir a mesma `idempotency_key`: a API
retorna `409 idempotency_conflict` para impedir que um retry perdido gere uma
capacidade diferente. Projetos também possuem um limite configurável de sessões
diretas por minuto; o padrão é 600.

## Contrato resumido

- tipos: `page_view`, `click`, `form_start`, `form_submit`, `conversion` e
  `custom`;
- `event_name`: identificador estável em minúsculas, como `hero.cta_clicked`;
- até 20 eventos por requisição e 32 KiB de corpo;
- a URL completa e seus parâmetros não são enviados: use apenas
  `location.pathname`;
- o dashboard fica em **Estatísticas → Rastreamento** e permite filtrar por
  projeto e período.
