# Spec curta — bootstrap Sun Ju e escopo global

## Baseline preservada

- Projetos continuam opcionais e N:N com experts por `project_memberships`.
- TAGs continuam organizacionais; autorização usa vínculos explícitos de projeto e RLS.
- Admin mantém a visão “Todos” e os fluxos atuais de WhatsApp, campanhas e opt-out.
- Nenhuma senha é persistida fora do Supabase Auth.

## Projeto e dados iniciais

- Criar de forma idempotente `[LC-AGO-26 SUN-JU]` na organização do número `909864832221280`.
- Criar a expert `Sun Ju` como rascunho sem e-mail, usuário Auth ou acesso efetivo.
- Associar a expert ao projeto; projeto sem expert continua válido.
- Associar ao projeto os contatos atuais, exceto contatos com TAG canônica `test`/`teste`.
- Associar conversas, mensagens e campanhas reais sem sobrescrever outro `project_id`; campanhas `is_test=true` ficam fora.

## Expert e autenticação

- Admin pode criar/editar expert rascunho, projetos e posteriormente ativar por convite ou senha inicial.
- Senha inicial atravessa somente a Edge Function e o Auth Admin; não é registrada nem devolvida.
- Rascunho/convite pendente não obtém acesso. Apenas usuário Auth vinculado e status aceito é expert ativo.

## Escopo e contatos

- Escopo global do admin: Todos, Projeto ou Expert. Expert expande para seus projetos.
- Contatos e conversas respeitam o escopo; settings permanecem administrativos.
- Cadastro/edição de contato inclui nome, e-mail, WhatsApp, TAGs e projetos.
- Alterar projetos preserva origens por TAG, importação e sistema.

## Mensagens

- Expert nunca envia template nem campanha.
- Expert responde somente mensagem WhatsApp dentro de 24 horas da última incoming da mesma conversa.
- A regra é aplicada no banco/backend; a UI apenas reflete e explica o bloqueio.

## Aceite focado

- Segunda execução do bootstrap não duplica nem altera contagens.
- Nenhum contato com TAG `test`/`teste`, campanha de teste ou conversa desse contato entra no projeto.
- Rascunho Sun Ju aparece ao admin, mas não autentica.
- Expert ativo não lê outro projeto, mensagem ambígua ou dado sem projeto.
- Template, conversa fora de 24h e projeto alheio retornam bloqueio no backend.
- Admin, dispatcher, worker, opt-out e campanhas existentes não sofrem regressão.
