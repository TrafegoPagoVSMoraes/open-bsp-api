# Tracking da página `/carta`

A página publicada em `https://sunju.com.br/carta` precisa instalar o coletor
descrito em `docs/TRACKING_INTEGRATION.md`. Sem esse JavaScript, o OpenBSP cria
um link individual por destinatário, mas a página não envia visualizações nem
cliques ao banco.

Use estes valores públicos na instalação:

```js
const endpoint =
  "https://wiqzhkxjraarkesqlwzl.supabase.co/functions/v1/tracking-events";
const projectKey = "ed7ea4b1-32db-4442-82d4-2e0b44aebc6b";
```

Antes de remover `#obsp=...` da URL, salve o token em
`sessionStorage.openbsp_tracking_session`. Marque cada botão com um nome
estável e único:

```html
<a id="carta-cta-principal" data-openbsp-event="carta.cta_principal_clicked">
  Acessar
</a>
```

Não coloque telefone, nome ou e-mail no HTML, na URL ou nos metadados. A
associação com o destinatário é feita no backend pelo token opaco e pelo
`message_id` do OpenBSP.

Validação depois da publicação:

1. abra uma URL real que contenha `#obsp=TOKEN`;
2. confirme que o fragmento desapareceu sem recarregar a página;
3. clique em cada botão instrumentado;
4. consulte **Estatísticas → Rastreamento → Atividade**;
5. confirme `page_view`, o nome de cada botão e o contato correspondente.
