[CmdletBinding()]
param(
  [string]$ConfigPath = '',
  [string]$CredentialPath = '',
  [string]$TokenCredentialPath = '',
  [string]$EnableMarkerPath = '',
  [string]$ConfigureLockPath = '',
  [string]$RuntimeLockPath = '',
  [ValidateRange(1, 65535)][int]$CorePort = 47841,
  [ValidateRange(15, 1440)][int]$TokenLifetimeMinutes = 240,
  [string]$SenderAddress = '',
  [string]$RecipientAddress = '',
  [string]$SmtpHost = '',
  [ValidateRange(0, 65535)][int]$SmtpPort = 0,
  [switch]$UsePasswordDialog,
  [switch]$EnableManualTest,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
function Assert-DistinctPaths([string[]]$Paths) {
  for ($left = 0; $left -lt $Paths.Length; $left++) {
    for ($right = $left + 1; $right -lt $Paths.Length; $right++) {
      if ([string]::Equals($Paths[$left], $Paths[$right], [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Shortcut mail relay paths must be distinct.'
      }
    }
  }
}
function ConvertTo-NormalizedGmailAppPassword([System.Security.SecureString]$SecurePassword) {
  $normalizedPassword = [System.Security.SecureString]::new()
  $nonWhitespaceCount = 0
  $whitespaceCount = 0
  $bstr = [IntPtr]::Zero
  try {
    if ($null -ne $SecurePassword) {
      $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    }
    for ($index = 0; $index -lt $SecurePassword.Length; $index++) {
      $character = [char][System.Runtime.InteropServices.Marshal]::ReadInt16($bstr, $index * 2)
      if ([char]::IsWhiteSpace($character)) {
        $whitespaceCount++
      } else {
        $normalizedPassword.AppendChar($character)
        $nonWhitespaceCount++
      }
    }
    if ($nonWhitespaceCount -ne 16) {
      $normalizedPassword.Dispose()
      $normalizedPassword = $null
    } else {
      $normalizedPassword.MakeReadOnly()
    }
    return [pscustomobject]@{
      NormalizedPassword = $normalizedPassword
      NonWhitespaceCount = $nonWhitespaceCount
      WhitespaceCount = $whitespaceCount
    }
  } finally {
    if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  }
}
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.json'
}
if ([string]::IsNullOrWhiteSpace($CredentialPath)) {
  $CredentialPath = Join-Path $scriptRoot '.state\shortcut-mail-smtp.credential.clixml'
}
if ([string]::IsNullOrWhiteSpace($TokenCredentialPath)) {
  $TokenCredentialPath = Join-Path $scriptRoot '.state\shortcut-mail-token.credential.clixml'
}
if ([string]::IsNullOrWhiteSpace($EnableMarkerPath)) {
  $EnableMarkerPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.enabled'
}
if ([string]::IsNullOrWhiteSpace($ConfigureLockPath)) {
  $ConfigureLockPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.configure.lock'
}
if ([string]::IsNullOrWhiteSpace($RuntimeLockPath)) {
  $RuntimeLockPath = Join-Path $scriptRoot '.state\shortcut-mail-relay.runtime.lock'
}
try {
  $ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
  $CredentialPath = [System.IO.Path]::GetFullPath($CredentialPath)
  $TokenCredentialPath = [System.IO.Path]::GetFullPath($TokenCredentialPath)
  $EnableMarkerPath = [System.IO.Path]::GetFullPath($EnableMarkerPath)
  $ConfigureLockPath = [System.IO.Path]::GetFullPath($ConfigureLockPath)
  $RuntimeLockPath = [System.IO.Path]::GetFullPath($RuntimeLockPath)
} catch { throw 'Shortcut mail relay paths are invalid.' }
Assert-DistinctPaths @($ConfigPath, $CredentialPath, $TokenCredentialPath, $EnableMarkerPath, $ConfigureLockPath, $RuntimeLockPath)
if (
  (Test-Path -LiteralPath $ConfigPath) -or
  (Test-Path -LiteralPath $CredentialPath) -or
  (Test-Path -LiteralPath $TokenCredentialPath)
) {
  if (-not $Force) { throw 'Existing relay configuration or credential found. Re-run with -Force to rotate it.' }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigureLockPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RuntimeLockPath) | Out-Null
if (Test-Path -LiteralPath $ConfigureLockPath -PathType Leaf) {
  try {
    $staleLock = [System.IO.File]::Open(
      [System.IO.Path]::GetFullPath($ConfigureLockPath),
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
    $staleLock.Dispose()
    Remove-Item -LiteralPath $ConfigureLockPath -Force
  } catch {
    throw 'Another Shortcut mail relay configuration is already in progress.'
  }
}
$configureLock = $null
$ownsConfigureLock = $false
$portGuard = $null
$runtimeLock = $null
$password = $null
$tokenSecure = $null
try {
  try {
    $configureLock = [System.IO.File]::Open(
      [System.IO.Path]::GetFullPath($ConfigureLockPath),
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    $ownsConfigureLock = $true
  } catch {
    throw 'Another Shortcut mail relay configuration is already in progress.'
  }

  try {
    $runtimeLock = [System.IO.File]::Open(
      [System.IO.Path]::GetFullPath($RuntimeLockPath),
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
  } catch {
    throw 'The Shortcut mail relay runtime is active or being started; configuration is closed.'
  }

  try {
    $portGuard = [System.Net.Sockets.TcpListener]::new(
      [System.Net.IPAddress]::Loopback,
      $CorePort
    )
    $portGuard.ExclusiveAddressUse = $true
    $portGuard.Start()
  } catch {
    throw "iCore may still be listening on 127.0.0.1:$CorePort, or the port could not be reserved. Stop HereIAm-iCore before configuring or rotating the relay."
  }
  # Disable the next service launch before any interactive wait or disk overwrite.
  if (Test-Path -LiteralPath $EnableMarkerPath) { Remove-Item -LiteralPath $EnableMarkerPath -Force -ErrorAction Stop }
  if (Test-Path -LiteralPath $EnableMarkerPath) { throw 'Shortcut mail relay could not be disabled for configuration.' }

$sender = if ([string]::IsNullOrWhiteSpace($SenderAddress)) {
  Read-Host 'SMTP sender address'
} else { $SenderAddress.Trim() }
$recipient = if ([string]::IsNullOrWhiteSpace($RecipientAddress)) {
  Read-Host 'Fixed recipient address'
} else { $RecipientAddress.Trim() }
if ([string]::IsNullOrWhiteSpace($SmtpHost)) {
  $SmtpHost = Read-Host 'SMTP host'
} else {
  $SmtpHost = $SmtpHost.Trim()
}
if ($SmtpPort -eq 0) {
  $smtpPortText = Read-Host 'SMTP port (default 587)'
  if ([string]::IsNullOrWhiteSpace($smtpPortText)) { $smtpPortText = '587' }
  if (-not [int]::TryParse($smtpPortText, [ref]$SmtpPort)) { throw 'SMTP port is invalid.' }
}
if ($SmtpPort -lt 1 -or $SmtpPort -gt 65535) { throw 'SMTP port is invalid.' }
if ([string]::IsNullOrWhiteSpace($sender) -or [string]::IsNullOrWhiteSpace($recipient) -or [string]::IsNullOrWhiteSpace($SmtpHost)) {
  throw 'Sender, recipient, and SMTP host are required.'
}
try {
  # PowerShell variable names are case-insensitive. Do not reuse the typed
  # SenderAddress / RecipientAddress parameter names for parsed objects.
  $parsedSender = [System.Net.Mail.MailAddress]::new($sender)
  $parsedRecipient = [System.Net.Mail.MailAddress]::new($recipient)
  if ($parsedSender.Address -ne $sender -or $parsedRecipient.Address -ne $recipient) { throw 'not canonical' }
} catch { throw 'Sender and recipient must be valid email addresses.' }

$passwordAlreadyNormalized = $false
if ($UsePasswordDialog) {
  Add-Type -AssemblyName PresentationFramework, PresentationCore
  $window = [System.Windows.Window]::new()
  # Keep this script ASCII-only so Windows PowerShell 5.1 decodes it reliably.
  $window.Title = 'Here I Am - Gmail SMTP setup'
  $window.Width = 520
  $window.Height = 300
  $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
  $window.ResizeMode = [System.Windows.ResizeMode]::NoResize
  $window.Topmost = $true

  $panel = [System.Windows.Controls.StackPanel]::new()
  $panel.Margin = [System.Windows.Thickness]::new(24)
  $title = [System.Windows.Controls.TextBlock]::new()
  $title.Text = 'Enter a NEW Gmail app password'
  $title.FontSize = 18
  $title.FontWeight = [System.Windows.FontWeights]::SemiBold
  [void]$panel.Children.Add($title)

  $description = [System.Windows.Controls.TextBlock]::new()
  $description.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
  $description.TextWrapping = [System.Windows.TextWrapping]::Wrap
  $description.Text = "Sender: $sender`nRecipient: $recipient`n`nPaste the 16-digit app password generated by Google. Google grouping whitespace is accepted and removed before saving. Do NOT use your Gmail sign-in password. Input is masked and is not saved to terminal history."
  [void]$panel.Children.Add($description)

  $passwordBox = [System.Windows.Controls.PasswordBox]::new()
  $passwordBox.Margin = [System.Windows.Thickness]::new(0, 16, 0, 0)
  $passwordBox.MinHeight = 36
  $passwordBox.FontSize = 18
  $passwordBox.PasswordChar = [char]0x25CF
  [void]$panel.Children.Add($passwordBox)

  $buttons = [System.Windows.Controls.StackPanel]::new()
  $buttons.Margin = [System.Windows.Thickness]::new(0, 18, 0, 0)
  $buttons.Orientation = [System.Windows.Controls.Orientation]::Horizontal
  $buttons.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
  $cancelButton = [System.Windows.Controls.Button]::new()
  $cancelButton.Content = 'Cancel'
  $cancelButton.Width = 88
  $cancelButton.IsCancel = $true
  $okButton = [System.Windows.Controls.Button]::new()
  $okButton.Content = 'Save securely'
  $okButton.Width = 100
  $okButton.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
  $okButton.IsDefault = $true
  $okButton.Add_Click({
    if ($null -ne $window.Tag) { $window.Tag.Dispose(); $window.Tag = $null }
    $normalization = ConvertTo-NormalizedGmailAppPassword $passwordBox.SecurePassword
    if ($null -eq $normalization.NormalizedPassword) {
      [void][System.Windows.MessageBox]::Show(
        $window,
        "Enter exactly 16 non-whitespace characters from a newly generated Gmail app password before saving. Received $($normalization.NonWhitespaceCount) non-whitespace characters and $($normalization.WhitespaceCount) whitespace characters.",
        'Invalid Gmail app password',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Warning
      )
      return
    }
    $window.Tag = $normalization.NormalizedPassword
    $window.DialogResult = $true
  })
  [void]$buttons.Children.Add($cancelButton)
  [void]$buttons.Children.Add($okButton)
  [void]$panel.Children.Add($buttons)
  $window.Content = $panel
  $window.Add_ContentRendered({ [void]$passwordBox.Focus() })

  if ($window.ShowDialog() -ne $true) {
    if ($null -ne $window.Tag) { $window.Tag.Dispose(); $window.Tag = $null }
    throw 'SMTP password entry was cancelled.'
  }
  $password = $window.Tag
  $window.Tag = $null
  $passwordBox.Clear()
  $passwordAlreadyNormalized = $true
} else {
  $password = Read-Host 'SMTP password' -AsSecureString
}
if (-not $passwordAlreadyNormalized) {
  $normalization = ConvertTo-NormalizedGmailAppPassword $password
  if ($null -eq $normalization.NormalizedPassword) {
    throw "Gmail app password must contain exactly 16 non-whitespace characters; received $($normalization.NonWhitespaceCount) non-whitespace characters and $($normalization.WhitespaceCount) whitespace characters."
  }
  $password.Dispose()
  $password = $normalization.NormalizedPassword
}
$credential = [System.Management.Automation.PSCredential]::new($sender, $password)

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CredentialPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TokenCredentialPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EnableMarkerPath) | Out-Null
$credential | Export-Clixml -LiteralPath $CredentialPath -Force
$tokenBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($tokenBytes) }
finally { $rng.Dispose() }
$token = [Convert]::ToBase64String($tokenBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$tokenSecure = ConvertTo-SecureString -String $token -AsPlainText -Force
$tokenCredential = [System.Management.Automation.PSCredential]::new('shortcut-mail-manual-test', $tokenSecure)
$tokenCredential | Export-Clixml -LiteralPath $TokenCredentialPath -Force
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try { $tokenHash = -join ($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($token)) | ForEach-Object { $_.ToString('x2') }) }
finally { $sha256.Dispose() }
$at = $recipient.IndexOf('@')
$receiverHint = if ($at -gt 1) { $recipient.Substring(0, 1) + '***' + $recipient.Substring($at) } else { 'configured-recipient' }
$config = [ordered]@{
  version = 1
  workflow = 'ios_shortcut_test_v0'
  sender = $sender
  recipient = $recipient
  receiver_hint = $receiverHint
  smtp = [ordered]@{ host = $SmtpHost; port = $SmtpPort; use_ssl = $true }
  credential_path = [System.IO.Path]::GetFullPath($CredentialPath)
  token_credential_path = [System.IO.Path]::GetFullPath($TokenCredentialPath)
  token_hash = $tokenHash
  token_expires_at_ms = [DateTimeOffset]::UtcNow.AddMinutes($TokenLifetimeMinutes).ToUnixTimeMilliseconds()
}
$configJson = $config | ConvertTo-Json -Depth 4
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($ConfigPath), $configJson, $utf8NoBom)
if ($EnableManualTest) {
  [System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($EnableMarkerPath),
    'enabled-v1',
    $utf8NoBom
  )
}
$token = $null
if ($null -ne $tokenSecure) { $tokenSecure.Dispose(); $tokenSecure = $null }
if ($null -ne $password) { $password.Dispose(); $password = $null }
if ($EnableManualTest) {
  Write-Output 'Shortcut mail relay configured and explicitly enabled. The scoped token remains DPAPI-protected; use copy_shortcut_mail_token.ps1 only when the Android debug page is ready.'
} else {
  Write-Output 'Shortcut mail relay configured but disabled. Re-run with -Force -EnableManualTest when the live manual Gate is ready.'
}
} finally {
  if ($null -ne $tokenSecure) { $tokenSecure.Dispose() }
  if ($null -ne $password) { $password.Dispose() }
  if ($null -ne $portGuard) { $portGuard.Stop() }
  if ($null -ne $runtimeLock) { $runtimeLock.Dispose() }
  if ($null -ne $configureLock) { $configureLock.Dispose() }
  if ($ownsConfigureLock) {
    Remove-Item -LiteralPath $ConfigureLockPath -Force -ErrorAction SilentlyContinue
  }
}
