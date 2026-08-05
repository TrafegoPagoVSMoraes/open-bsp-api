# ADR-0002: Tokens opacos e minimização de dados

- Status: aceito
- Data: 2026-08-05

## Contexto

Links e sessões públicos precisam atribuir eventos sem expor telefone, contato,
organização ou IDs internos. Telemetria detalhada também aumenta o risco de
privacidade e o custo de retenção.

## Decisão

Links e sessões usam tokens aleatórios de 256 bits. O token público circula
somente na URL de redirecionamento ou no fragmento `#obsp`; o banco persiste
apenas SHA-256. O fragmento é removido pela integração assim que a página o lê.

O modelo padrão não armazena IP bruto, cidade, latitude, longitude nem user
agent completo. Mantém apenas navegador, sistema, tipo de dispositivo,
país/região e referenciador sem query string. Metadados têm tamanho limitado e
filtros de dados pessoais. A retenção detalhada é configurável por projeto e
executada diariamente.

## Consequências

- vazamentos de banco não revelam links ou sessões ainda utilizáveis;
- URLs não carregam telefone, nome ou identificadores internos;
- a análise perde precisão geográfica deliberadamente;
- a atribuição individual continua possível quando o link possui `message_id`;
- logs e dashboard não exibem tokens e mascaram o endereço do contato.
