param([string]$SourcePath,[string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors);if($errors.Count){throw 'source_parse_failed'}
$command=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName()-eq 'Add-Type'},$true))[0]
Add-Type -TypeDefinition $command.CommandElements[2].Value
foreach($name in @('Pin-File','Assert-Private')){
 $f=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq $name},$true));if($f.Count-ne 1){throw 'fixture_function_not_unique'};Invoke-Expression $f[0].Extent.Text
}
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$file=Join-Path $FixtureParent 'synthetic-pin.txt';[IO.File]::WriteAllText($file,'synthetic-pin',[Text.UTF8Encoding]::new($false))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.FileSecurity;$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
foreach($id in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,'FullControl','Allow'))}
[IO.File]::SetAccessControl($file,$acl)
try{
 foreach($hash in @('','short')){try{Pin-File $file $hash;throw 'empty_anchor_accepted'}catch{if($_.Exception.Message-cne 'sha256_anchor_required'){throw}}}
 $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();Pin-File $file $hash
 try{Pin-File $file ('0'*64);throw 'wrong_anchor_accepted'}catch{if($_.Exception.Message-cne 'file_hash_changed'){throw}}
 try{Pin-File $file $hash -ReceiptWithoutExternalHash;throw 'ambiguous_receipt_exception_accepted'}catch{if($_.Exception.Message-cne 'receipt_pin_shape_rejected'){throw}}
 Pin-File $file '' -ReceiptWithoutExternalHash
 [Console]::WriteLine('{"passed":true,"emptyAndMalformedRejected":true,"correctHashPinned":true,"wrongHashRejected":true,"receiptExceptionExplicit":true}')
}finally{foreach($h in $locks){$h.Dispose()}}
