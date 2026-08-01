# Implantação do OpenBSP

## Arquitetura

```text
OpenBSP UI (React/Vite)
  -> Cloudflare Pages
  -> Supabase JS, HTTPS e Realtime
OpenBSP API
  -> Supabase Postgres, Auth, Storage e Edge Functions
  -> Meta WhatsApp Business Cloud API
```

Esta implantação é independente do Forteens. Ela não usa o banco nem o frontend
do Forteens e não move as Edge Functions para Cloudflare Workers.

## Serviços

- UI: https://open-bsp.pages.dev
- Supabase: projeto `open-bsp`, região `sa-east-1`
- API: https://wiqzhkxjraarkesqlwzl.supabase.co
- Webhook: https://wiqzhkxjraarkesqlwzl.supabase.co/functions/v1/whatsapp-webhook
- Fork da API: https://github.com/TrafegoPagoVSMoraes/open-bsp-api
- Fork da UI: https://github.com/TrafegoPagoVSMoraes/open-bsp-ui

## Configuração sem valores

Segredos do workflow da API:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_SERVICE_ROLE_KEY`
- `META_SYSTEM_USER_ID`
- `META_SYSTEM_USER_ACCESS_TOKEN`
- `META_APP_ID`
- `META_APP_SECRET`
- `WHATSAPP_VERIFY_TOKEN`

Variáveis do workflow da API:

- `SUPABASE_PROJECT_ID`
- `SUPABASE_SESSION_POOLER_HOST`

Variáveis públicas do frontend:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_META_APP_ID` (opcional)
- `VITE_FB_LOGIN_CONFIG_ID` (opcional)

Nunca publique no frontend a service role, o App Secret, tokens da Meta ou o
token de verificação do webhook.

## Deploy da API

O mecanismo único de produção é o workflow oficial `Release` do repositório.
A integração automática Supabase/GitHub fica desativada para evitar dois
pipelines concorrentes.

1. Atualize os segredos e variáveis em GitHub Actions.
2. Execute o workflow `Release` na branch `main`.
3. Confirme que `supabase db push`, `supabase functions deploy` e a configuração
   do Vault terminaram com sucesso.
4. Verifique as funções com `npx supabase functions list --project-ref <ref>`.

## Deploy da UI

1. Execute `npm install`.
2. Configure apenas as variáveis públicas `VITE_*`.
3. Execute `npm run build`.
4. Publique `dist` no projeto Cloudflare Pages `open-bsp`, branch `main`.
5. Teste a raiz e uma rota interna diretamente para validar o fallback SPA.

## Atualização pelo upstream

```bash
git fetch upstream
git checkout main
git merge --ff-only upstream/main
git push origin main
```

Se não for possível avançar com `--ff-only`, revise a divergência em uma branch
separada. Não faça push forçado na `main`.

## Webhook da Meta

1. Confirme que os cinco segredos `META_*`/`WHATSAPP_VERIFY_TOKEN` estão nas
   Edge Functions.
2. Teste o challenge na URL do webhook antes de substituir o endpoint atual.
3. Na Meta, configure a Callback URL e use exatamente o mesmo Verify Token.
4. Assine somente: `account_update`, `messages`, `history`,
   `smb_app_state_sync`, `smb_message_echoes` e `user_id_update`.
5. Envie o teste de `messages` e confira o log da função sem registrar payloads
   sensíveis.

## Rollback

- API: execute novamente o workflow `Release` a partir do último commit estável.
- UI: promova no Cloudflare Pages um deployment anterior conhecido como bom.
- Webhook: mantenha registrada a URL anterior e só a restaure se o novo endpoint
  deixar de responder ao challenge ou aos eventos.

## Diagnóstico básico

Verifique, nesta ordem: deployment do Pages, console/rede do navegador,
Supabase Auth, RLS, Realtime, logs das Edge Functions, migrations, segredos,
configuração do webhook e permissões do usuário de sistema da Meta.

Não desative RLS, não use service role no navegador e não troque a Cloud API por
automação de WhatsApp Web.

## Limites gratuitos

Supabase e Cloudflare aplicam cotas de banco, armazenamento, execução, banda e
build. Monitore o painel de uso. O tráfego e as conversas cobrados pela Meta não
fazem parte dos planos gratuitos desses provedores.
