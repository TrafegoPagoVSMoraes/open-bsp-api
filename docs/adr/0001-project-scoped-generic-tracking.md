# ADR-0001: Rastreamento genérico orientado a projetos

- Status: aceito
- Data: 2026-08-05

## Contexto

O primeiro protótipo de rastreamento estava vinculado a uma página, rota,
template e conjunto de botões específicos. Isso impedia o reuso em outros sites
e misturava a plataforma de eventos com o transporte WhatsApp.

## Decisão

O contexto de rastreamento será organizado por `tracking_projects`. Cada projeto
pertence a uma organização e define origens autorizadas, retenção e tempo de
sessão. Links, sessões e eventos sempre carregam `project_id` e
`organization_id` determinados no servidor.

`message_id` é opcional. Quando existe, preserva a atribuição a uma mensagem do
OpenBSP; quando não existe, o mesmo núcleo atende páginas, campanhas e outros
canais. O navegador nunca informa IDs de organização, mensagem ou contato.

## Consequências

- o backend serve qualquer página HTTPS previamente autorizada;
- o WhatsApp é um adaptador opcional, não uma dependência do rastreador;
- CORS e destinos são validados por projeto;
- métricas gerais e por projeto compartilham o mesmo modelo;
- campanhas e disparos normalizados poderão ser acrescentados depois, sem
  bloquear o núcleo atual.
