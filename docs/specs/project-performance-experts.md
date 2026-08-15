# Spec curta — Projetos, performance e isolamento

## Baseline preservada

- `organizations` continua sendo o tenant principal.
- `contacts`, `contact_tags` e seleção de campanhas por TAG continuam funcionando.
- `campaigns` de WhatsApp não é renomeada nem reutilizada como métrica de tráfego pago.
- Registros antigos sem projeto continuam acessíveis para administradores.
- O mesmo número de WhatsApp continua atendendo todos os projetos.

## Fase 1 — raiz Projeto e performance

- `projects`: projeto por organização, orçamento planejado, status e identificador estável.
- `project_tags`: associação N:N com tags existentes; serve para organização e sincronização, não para autorização.
- `project_contacts`: associação explícita N:N e futura fonte de autorização.
- `project_import_aliases`: nomes/IDs externos aceitos na importação.
- `project_performance_daily`: uma linha por projeto/data, com gasto, leads, entradas no grupo, alcance e observações. CPL é calculado.
- Interface autenticada com projeto ativo, CRUD simples, tabela diária, totais, edição manual e importação CSV/XLSX com preview.
- Importação agrega linhas do mesmo dia e permite escolher inserir, substituir ou ignorar conflitos.

## Fase 2 — experts e isolamento

- Expert é um `agent` humano do Supabase Auth com `extra.account_type = expert`.
- `project_memberships` associa um usuário a vários projetos.
- Owner/admin da organização vê todos os projetos; experts veem somente memberships.
- Usuários legados que não são experts preservam o comportamento atual.
- RLS de projeto usa memberships explícitas, nunca tags.

## Fase 2A — contatos e mensagens

- Expert vê contatos por `project_contacts`.
- `project_conversations` registra quais conversas pertencem a cada projeto.
- `messages.project_id` é opcional e identifica o contexto da mensagem.
- Saída iniciada em um projeto exige projeto explícito.
- Entrada é atribuída automaticamente apenas quando o contato pertence a exatamente um projeto; zero ou múltiplos projetos ficam sem atribuição e somente o administrador pode classificá-la.

## Fase 3 — scheduler

- Instrumentar tempo de claim, preparação, inserção e resposta do dispatcher antes de otimizar.
- Preservar idempotência por destinatário/campanha e nunca reenfileirar estados ambíguos.
- Concorrência limitada e configurável somente se o gargalo estiver no worker, com padrão conservador.
- Testar com mocks/fixtures; nenhum disparo real em massa.

## Critérios de aceite focados

1. Fluxos antigos de tags e campanhas continuam válidos.
2. Projeto/data não gera duplicidade não intencional.
3. Preview de importação separa inserções, atualizações, ignoradas e rejeitadas.
4. Expert A não lê dados do Projeto B.
5. Mensagens ambíguas não aparecem para experts.
6. Scheduler mantém teto e chave idempotente.
