# Loaded only after the release inventory and bootstrap hashes are verified.
# The MCP program is a separately fixed source tree; no source is rewritten.
function Read-Schema6McpConfiguration($Login, [ref]$Locks) {
  $names=@($Login.PSObject.Properties.Name)
  if('mcp_configuration_path' -notin $names){return ''}
  if($null -eq $Login.mcp_configuration_path -and $null -eq $Login.mcp_configuration_sha256){return ''}
  $file=$Login.mcp_configuration_path
  Assert-ProtectedPath ([IO.Path]::GetDirectoryName($file)) -Root
  $Locks.Value += Open-BootstrapFile $file
  if($Login.mcp_configuration_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $Login.mcp_configuration_sha256){throw 'mcp_configuration_hash_mismatch'}
  $value=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
  $expected=@('format','owner_sid','executable_path','executable_sha256','working_directory','entrypoint','source_files','arguments','environment','database_path','listen_host','listen_port','grace_ms')
  if(@(Compare-Object ($expected|Sort-Object) ($value.PSObject.Properties.Name|Sort-Object)).Count -ne 0 -or $value.format -ne 'schema6-mcp-v1' -or $value.owner_sid -ne $Login.owner_sid){throw 'mcp_configuration_contract_invalid'}
  if($value.database_path -cne (Join-Path $Login.state_directory 'i-core.sqlite') -or $value.listen_host -cne '127.0.0.1' -or $value.listen_port -isnot [int] -or $value.listen_port -lt 1 -or $value.listen_port -gt 65535 -or $value.listen_port -eq $Login.core_port -or $value.grace_ms -isnot [int] -or $value.grace_ms -lt 0 -or $value.grace_ms -gt 3000){throw 'mcp_binding_invalid'}
  Assert-ProtectedPath $value.working_directory -Root
  # State/configuration files belong outside the immutable MCP source tree.
  foreach($directory in @($Login.state_directory,$Login.control_root)){
    if($directory -eq $value.working_directory -or $directory.StartsWith($value.working_directory+'\',[StringComparison]::OrdinalIgnoreCase) -or $value.working_directory.StartsWith($directory+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'mcp_source_state_overlap'}
  }
  $Locks.Value += Open-BootstrapFile $value.executable_path
  if($value.executable_sha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $value.executable_path -Algorithm SHA256).Hash -ne $value.executable_sha256){throw 'mcp_executable_hash_mismatch'}
  if($value.source_files -isnot [array] -or $value.source_files.Count -lt 1){throw 'mcp_inventory_required'}
  $listed=@()
  foreach($entry in $value.source_files){
    if(@(Compare-Object @('path','sha256') @($entry.PSObject.Properties.Name|Sort-Object)).Count -ne 0 -or $entry.path -notmatch '^[A-Za-z0-9_./-]+$' -or $entry.path.Contains('..') -or $entry.path.StartsWith('/') -or $entry.path.EndsWith('/') -or $entry.sha256 -notmatch '^[a-f0-9]{64}$' -or $listed -contains $entry.path){throw 'mcp_inventory_entry_invalid'}
    $target=Join-Path $value.working_directory $entry.path
    $Locks.Value += Open-BootstrapFile $target
    if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256){throw 'mcp_source_hash_mismatch'}
    $listed += $entry.path
  }
  $actual=@()
  foreach($item in Get-ChildItem -LiteralPath $value.working_directory -Recurse -Force){
    Assert-ProtectedPath $item.FullName
    if(-not $item.PSIsContainer){$actual += $item.FullName.Substring($value.working_directory.Length+1).Replace('\','/')}
  }
  if(@(Compare-Object ($listed|Sort-Object) ($actual|Sort-Object)).Count -ne 0 -or $value.entrypoint -cnotin $listed){throw 'mcp_source_inventory_mismatch'}
  if($value.arguments -isnot [array]){throw 'mcp_arguments_invalid'}
  foreach($argument in $value.arguments){
    if($argument -isnot [string] -or $argument.Contains('"') -or $argument.Contains([char]0) -or $argument.Contains([char]13) -or $argument.Contains([char]10) -or $argument.EndsWith('\') -or $argument -match '^--(core-db|core-url|host|port|state-dir|memory-db|policy)(=|$)'){throw 'mcp_bound_argument_override'}
  }
  if($null -eq $value.environment -or $value.environment -isnot [pscustomobject]){throw 'mcp_environment_invalid'}
  $envNames=@($value.environment.PSObject.Properties.Name)
  foreach($property in $value.environment.PSObject.Properties){
    if($property.Name -cnotmatch '^(I_|SCHEMA6_TEST_)[A-Z0-9_]+$' -or $property.Name -in @('I_CORE_DB','I_CORE_URL','I_REMOTE_MCP_HOST','I_REMOTE_MCP_PORT') -or $property.Value -isnot [string] -or $property.Value.Contains([char]0)){throw 'mcp_environment_invalid'}
  }
  foreach($key in @('I_REMOTE_MCP_STATE_DIR','I_MEMORY_DB','I_MEMORY_POLICY','I_HOME')){
    if($key -notin $envNames){throw 'mcp_explicit_data_paths_required'}
    $target=$value.environment.$key
    if($key -in @('I_REMOTE_MCP_STATE_DIR','I_HOME')){Assert-ProtectedPath $target -Root}
    else{Assert-ProtectedPath $target;$probe=Open-BootstrapFile $target;$probe.Dispose()}
    if($target -eq $value.working_directory -or $target.StartsWith($value.working_directory+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'mcp_source_data_overlap'}
  }
  return ($value | ConvertTo-Json -Depth 12 -Compress)
}
