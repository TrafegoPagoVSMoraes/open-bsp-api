param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9]+@g\.us$')]
  [string] $GroupJid,

  [string] $TagSlug = 'sunju-vip',
  [string] $SenderPhoneNumberId = '909864832221280',
  [string] $EnvFile = (Join-Path $PSScriptRoot '..\.secrets\wasenderapi.env'),
  [string] $Extractor = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Extrair-Membros-WasenderAPI.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EnvFile)) {
  throw "Arquivo de credencial não encontrado: $EnvFile"
}
if (-not (Test-Path -LiteralPath $Extractor)) {
  throw "Extrator WasenderAPI não encontrado: $Extractor"
}

$keyLine = Get-Content -LiteralPath $EnvFile |
  Where-Object { $_ -match '^\s*WASENDER_API_KEY\s*=' } |
  Select-Object -First 1
if (-not $keyLine) { throw 'WASENDER_API_KEY não encontrada.' }
$apiKey = ($keyLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'WASENDER_API_KEY vazia.' }

# Reuse the corrected extractor without copying the secret into its source.
$source = Get-Content -LiteralPath $Extractor -Raw
$escapedKey = $apiKey.Replace("'", "''")
$source = [regex]::Replace(
  $source,
  '(?m)^\$ApiKey\s*=.*$',
  "`$ApiKey = '$escapedKey'"
)
$source = [regex]::Replace(
  $source,
  '(?m)^\$GroupJid\s*=.*$',
  "`$GroupJid = '$GroupJid'"
)
& ([scriptblock]::Create($source))

$groupNumber = $GroupJid.Replace('@g.us', '')
$extractionsRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Wasender-Extracoes'
$latest = Get-ChildItem -LiteralPath $extractionsRoot -Directory |
  Where-Object { $_.Name -like "$groupNumber-*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $latest) { throw 'A extração não gerou uma pasta de resultado.' }

$csvPath = Join-Path $latest.FullName 'membros.csv'
$phones = Import-Csv -LiteralPath $csvPath -Delimiter ';' |
  ForEach-Object { $_.Telefone } |
  Where-Object { $_ -match '^[1-9][0-9]{9,14}$' } |
  Sort-Object -Unique
if (-not $phones.Count) { throw 'Nenhum telefone válido foi extraído.' }

$values = $phones | ForEach-Object { "('$_','$(New-Guid)')" }
$valuesSql = $values -join ','
$safeTagSlug = $TagSlug.Replace("'", "''")
$safeGroup = $GroupJid.Replace("'", "''")

$sql = @"
begin;
create temp table tmp_wasender_sync(
  phone text primary key,
  contact_id uuid not null
) on commit drop;
insert into tmp_wasender_sync values $valuesSql;

insert into contacts(organization_id,id,name,extra)
select org.organization_id, input.contact_id, null,
  jsonb_build_object('source','wasender_group','group_id','$safeGroup')
from tmp_wasender_sync input
cross join lateral (
  select organization_id from organizations_addresses
  where address='$SenderPhoneNumberId' and service='whatsapp' limit 1
) org
where not exists (
  select 1 from contacts_addresses address
  where address.organization_id=org.organization_id
    and address.service='whatsapp' and address.address=input.phone
    and address.contact_id is not null
);

insert into contacts_addresses(
  organization_id,service,address,status,contact_id
)
select org.organization_id,'whatsapp',input.phone,'active',input.contact_id
from tmp_wasender_sync input
cross join lateral (
  select organization_id from organizations_addresses
  where address='$SenderPhoneNumberId' and service='whatsapp' limit 1
) org
on conflict(organization_id,service,address) do nothing;

update contacts_addresses address set contact_id=input.contact_id
from tmp_wasender_sync input
where address.organization_id=(
  select organization_id from organizations_addresses
  where address='$SenderPhoneNumberId' and service='whatsapp' limit 1
)
and address.service='whatsapp' and address.address=input.phone
and address.contact_id is null;

delete from contacts contact using tmp_wasender_sync input
where contact.id=input.contact_id and not exists (
  select 1 from contacts_addresses address
  where address.contact_id=contact.id
    and address.organization_id=contact.organization_id
);

insert into contact_tags(organization_id,contact_id,tag_id,source)
select address.organization_id,address.contact_id,tag.id,'wasender_group'
from tmp_wasender_sync input
join contacts_addresses address
  on address.address=input.phone and address.service='whatsapp'
  and address.organization_id=(
    select organization_id from organizations_addresses
    where address='$SenderPhoneNumberId' and service='whatsapp' limit 1
  )
join tags tag on tag.organization_id=address.organization_id
  and tag.slug='$safeTagSlug'
where address.contact_id is not null
on conflict do nothing;

select count(distinct address.address) synced,
  count(distinct membership.contact_id) tagged
from tmp_wasender_sync input
join contacts_addresses address
  on address.address=input.phone and address.service='whatsapp'
join contact_tags membership
  on membership.organization_id=address.organization_id
  and membership.contact_id=address.contact_id
join tags tag on tag.id=membership.tag_id
  and tag.organization_id=membership.organization_id
  and tag.slug='$safeTagSlug';
commit;
"@

$tempSql = Join-Path ([System.IO.Path]::GetTempPath()) ("openbsp-wasender-sync-" + [guid]::NewGuid().ToString() + ".sql")
try {
  # Passing a multiline statement as a positional CLI argument is unreliable on
  # Windows. A temporary file keeps the operation atomic and preserves phone
  # identifiers exactly as extracted.
  [System.IO.File]::WriteAllText(
    $tempSql,
    $sql,
    (New-Object System.Text.UTF8Encoding($false))
  )
  & npx.cmd --yes supabase@2.87.1 db query --linked --file $tempSql
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao sincronizar contatos no OpenBSP.' }
}
finally {
  Remove-Item -LiteralPath $tempSql -Force -ErrorAction SilentlyContinue
}

Write-Host "Sincronização concluída: $($phones.Count) telefones; TAG $TagSlug."
