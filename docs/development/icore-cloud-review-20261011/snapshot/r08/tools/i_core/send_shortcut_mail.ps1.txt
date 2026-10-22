[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ConfigPath,
  [string]$ReceiptId,
  [Int64]$RequestedAtMs,
  [switch]$AuthenticationProbe
)

$ErrorActionPreference = 'Stop'
$script:transportBudgetMs = 35000
$script:transportStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Get-TransportRemainingMs([int]$MaximumOperationMs) {
  $remainingMs = $script:transportBudgetMs - [int]$script:transportStopwatch.ElapsedMilliseconds
  if ($remainingMs -le 0) { throw 'SMTP transport deadline exceeded.' }
  return [Math]::Min($remainingMs, $MaximumOperationMs)
}

function Set-SmtpIoDeadline([System.IO.Stream]$Stream) {
  $operationMs = Get-TransportRemainingMs 12000
  if ($Stream.CanTimeout) {
    $Stream.ReadTimeout = $operationMs
    $Stream.WriteTimeout = $operationMs
  }
}

function Read-SmtpLine([System.IO.StreamReader]$Reader) {
  $lineBuilder = [System.Text.StringBuilder]::new()
  for ($characterCount = 0; $characterCount -le 4096; $characterCount++) {
    Set-SmtpIoDeadline $Reader.BaseStream
    $characterCode = $Reader.Read()
    if ($characterCode -lt 0) { throw 'SMTP response ended unexpectedly.' }
    if ($characterCode -eq 13) {
      Set-SmtpIoDeadline $Reader.BaseStream
      if ($Reader.Read() -ne 10) { throw 'SMTP response line ending is invalid.' }
      return $lineBuilder.ToString()
    }
    if ($characterCode -eq 10) { throw 'SMTP response line ending is invalid.' }
    if ($characterCount -eq 4096) { throw 'SMTP response line is oversized.' }
    [void]$lineBuilder.Append([char]$characterCode)
  }
}

function Read-SmtpReply(
  [System.IO.StreamReader]$Reader,
  [int[]]$ExpectedCodes,
  [string]$Stage
) {
  $replyCode = 0
  $firstReplyCode = 0
  $replyCharacterCount = 0
  $replyLines = [System.Collections.Generic.List[string]]::new()
  for ($lineCount = 0; $lineCount -lt 100; $lineCount++) {
    $line = Read-SmtpLine $Reader
    $replyCharacterCount += $line.Length + 2
    if ($replyCharacterCount -gt 32768) {
      throw "SMTP $Stage failed with an oversized response."
    }
    if ($null -eq $line -or $line.Length -lt 3 -or
        -not [int]::TryParse($line.Substring(0, 3), [ref]$replyCode)) {
      throw "SMTP $Stage failed with an invalid response."
    }
    if ($lineCount -eq 0) { $firstReplyCode = $replyCode }
    if ($replyCode -ne $firstReplyCode) {
      throw "SMTP $Stage failed with an invalid response."
    }
    [void]$replyLines.Add($line)
    if ($line.Length -eq 3 -or $line[3] -eq ' ') {
      if ($ExpectedCodes -notcontains $replyCode) {
        throw "SMTP $Stage failed."
      }
      return [pscustomobject]@{ Code = $replyCode; Lines = @($replyLines) }
    }
    if ($line[3] -ne '-') {
      throw "SMTP $Stage failed with an invalid response."
    }
  }
  throw "SMTP $Stage failed with an oversized response."
}

function Send-SmtpCommand(
  [System.IO.StreamWriter]$Writer,
  [System.IO.StreamReader]$Reader,
  [string]$Command,
  [int[]]$ExpectedCodes,
  [string]$Stage
) {
  if ($Command.IndexOf("`r") -ge 0 -or $Command.IndexOf("`n") -ge 0) {
    throw "SMTP $Stage command is invalid."
  }
  Set-SmtpIoDeadline $Writer.BaseStream
  $Writer.Write($Command)
  $Writer.Write("`r`n")
  $Writer.Flush()
  return Read-SmtpReply -Reader $Reader -ExpectedCodes $ExpectedCodes -Stage $Stage
}

function New-SmtpTextReader([System.IO.Stream]$Stream) {
  return [System.IO.StreamReader]::new(
    $Stream,
    [System.Text.Encoding]::ASCII,
    $false,
    1024,
    $true
  )
}

function New-SmtpTextWriter([System.IO.Stream]$Stream) {
  $writer = [System.IO.StreamWriter]::new(
    $Stream,
    [System.Text.UTF8Encoding]::new($false),
    1024,
    $true
  )
  $writer.NewLine = "`r`n"
  return $writer
}

function Connect-SmtpIPv4(
  [string]$SmtpHost,
  [int]$SmtpPort,
  [int]$ConnectTimeoutMs
) {
  $dnsLookup = [System.Net.Dns]::BeginGetHostAddresses($SmtpHost, $null, $null)
  try {
    $dnsWaitMs = Get-TransportRemainingMs 5000
    if (-not $dnsLookup.AsyncWaitHandle.WaitOne($dnsWaitMs)) {
      throw 'SMTP DNS resolution timed out.'
    }
    $resolvedAddresses = [System.Net.Dns]::EndGetHostAddresses($dnsLookup)
  } finally {
    $dnsLookup.AsyncWaitHandle.Close()
  }
  $ipv4Addresses = @(
    $resolvedAddresses |
      Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
      Sort-Object -Property IPAddressToString -Unique |
      Select-Object -First 8
  )
  if ($ipv4Addresses.Count -eq 0) {
    throw 'SMTP DNS resolution returned no IPv4 addresses.'
  }

  foreach ($ipv4Address in $ipv4Addresses) {
    $tcpClient = [System.Net.Sockets.TcpClient]::new(
      [System.Net.Sockets.AddressFamily]::InterNetwork
    )
    $tcpClient.ReceiveTimeout = 12000
    $tcpClient.SendTimeout = 12000
    $connectSucceeded = $false
    try {
      $connect = $tcpClient.BeginConnect($ipv4Address, $SmtpPort, $null, $null)
      try {
        $connectWaitMs = Get-TransportRemainingMs $ConnectTimeoutMs
        if (-not $connect.AsyncWaitHandle.WaitOne($connectWaitMs)) {
          throw 'SMTP TCP connection timed out.'
        }
        $tcpClient.EndConnect($connect)
        $connectSucceeded = $true
      } finally {
        $connect.AsyncWaitHandle.Close()
      }
      return $tcpClient
    } catch {
      $tcpClient.Dispose()
      if ($connectSucceeded) {
        throw 'SMTP TCP connection failed after it was established; failover is forbidden.'
      }
    }
  }
  throw 'SMTP TCP connection failed for every resolved IPv4 address.'
}

function ConvertTo-Rfc2047Utf8([string]$Value) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  try {
    return '=?UTF-8?B?' + [Convert]::ToBase64String($bytes) + '?='
  } finally {
    [System.Array]::Clear($bytes, 0, $bytes.Length)
  }
}

function Assert-AsciiMailbox([string]$Mailbox, [string]$Label) {
  $parsed = [System.Net.Mail.MailAddress]::new($Mailbox)
  if (-not $parsed.Address.Equals($Mailbox, [System.StringComparison]::OrdinalIgnoreCase) -or
      $Mailbox.IndexOf("`r") -ge 0 -or $Mailbox.IndexOf("`n") -ge 0 -or
      $Mailbox.IndexOf('<') -ge 0 -or $Mailbox.IndexOf('>') -ge 0 -or
      $Mailbox -match '[^\x20-\x7e]') {
    throw "$Label mailbox is invalid."
  }
  return $parsed.Address
}

function Invoke-SmtpEnvelope(
  [System.IO.StreamWriter]$Writer,
  [System.IO.StreamReader]$Reader,
  [string]$Sender,
  [string]$Recipient,
  [string[]]$MessageLines,
  [switch]$AuthenticationProbe
) {
  if ($AuthenticationProbe) {
    $null = Send-SmtpCommand -Writer $Writer -Reader $Reader -Command 'QUIT' -ExpectedCodes @(221) -Stage 'QUIT'
    return [pscustomobject]@{ authenticated = $true; message_sent = $false }
  }

  $null = Send-SmtpCommand -Writer $Writer -Reader $Reader -Command "MAIL FROM:<$Sender>" -ExpectedCodes @(250) -Stage 'MAIL FROM'
  $null = Send-SmtpCommand -Writer $Writer -Reader $Reader -Command "RCPT TO:<$Recipient>" -ExpectedCodes @(250, 251) -Stage 'RCPT TO'
  $null = Send-SmtpCommand -Writer $Writer -Reader $Reader -Command 'DATA' -ExpectedCodes @(354) -Stage 'DATA'

  foreach ($messageLine in $MessageLines) {
    if ($messageLine.StartsWith('.')) { $messageLine = '.' + $messageLine }
    Set-SmtpIoDeadline $Writer.BaseStream
    $Writer.Write($messageLine)
    $Writer.Write("`r`n")
  }
  Set-SmtpIoDeadline $Writer.BaseStream
  $Writer.Write(".`r`n")
  $Writer.Flush()
  $null = Read-SmtpReply -Reader $Reader -ExpectedCodes @(250) -Stage 'message acceptance'

  # DATA's final 250 is the sole acceptance boundary. QUIT is best-effort only:
  # a later failure must not turn a known acceptance into unknown.
  try {
    $null = Send-SmtpCommand -Writer $Writer -Reader $Reader -Command 'QUIT' -ExpectedCodes @(221) -Stage 'QUIT after acceptance'
  } catch {}
  return [pscustomobject]@{ accepted = $true }
}

# SMTP runtime starts here.
try {
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
  throw 'Relay configuration could not be loaded.'
}
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'strict_smtp_tls_validation.ps1')
if ($config.workflow -ne 'ios_shortcut_test_v0') { throw 'Unsupported relay workflow.' }
if (-not $config.sender -or -not $config.recipient -or -not $config.smtp.host -or -not $config.credential_path) {
  throw 'Relay configuration is incomplete.'
}
if ($config.smtp.use_ssl -ne $true) { throw 'TLS is mandatory for the Shortcut mail relay.' }
if (-not $AuthenticationProbe -and (-not $ReceiptId -or $RequestedAtMs -le 0)) {
  throw 'ReceiptId and RequestedAtMs are mandatory for a mail send.'
}
if (-not $AuthenticationProbe) {
  $parsedReceiptId = [Guid]::Empty
  if (-not [Guid]::TryParseExact($ReceiptId, 'D', [ref]$parsedReceiptId)) {
    throw 'ReceiptId must be a canonical UUID.'
  }
}

$smtpHost = [string]$config.smtp.host
$smtpPort = [int]$config.smtp.port
if (-not $smtpHost.Equals('smtp.gmail.com', [System.StringComparison]::OrdinalIgnoreCase) -or $smtpPort -ne 587) {
  throw 'The Shortcut mail relay is pinned to smtp.gmail.com port 587.'
}
$sender = Assert-AsciiMailbox -Mailbox ([string]$config.sender) -Label 'Sender'
$recipient = Assert-AsciiMailbox -Mailbox ([string]$config.recipient) -Label 'Recipient'
$messageLines = $null
if (-not $AuthenticationProbe) {
  $requestedUtc = [DateTimeOffset]::FromUnixTimeMilliseconds($RequestedAtMs).UtcDateTime.ToString('o')
  $subject = -join ([int[]](0x54C4, 0x7761, 0x804A, 0x5929) | ForEach-Object { [char]$_ })
  $encodedSubject = ConvertTo-Rfc2047Utf8 $subject
  $body = "Fixed-template iOS Shortcut relay test.`r`nReceipt: $ReceiptId`r`nRequested UTC: $requestedUtc"
  $messageLines = @(
    "From: <$sender>",
    "To: <$recipient>",
    "Subject: $encodedSubject",
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 7bit',
    '',
    ($body -split "`r?`n")
  )
}
try {
  $credential = Import-Clixml -LiteralPath $config.credential_path
} catch {
  throw 'SMTP credential could not be loaded.'
}
if ($credential -isnot [System.Management.Automation.PSCredential]) { throw 'Invalid SMTP credential.' }

$networkCredential = $credential.GetNetworkCredential()
$tcpClient = $null
$networkStream = $null
$sslStream = $null
$reader = $null
$writer = $null
try {
  if (-not $networkCredential.UserName -or -not $networkCredential.Password) {
    throw 'Invalid SMTP credential.'
  }
  if (-not $networkCredential.UserName.Equals($sender, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'SMTP credential username must match the fixed sender.'
  }

  # IPv4 failover is confined to this function. Once it returns one connected
  # socket, no TLS, AUTH, or message failure is retried on another address.
  $tcpClient = Connect-SmtpIPv4 -SmtpHost $smtpHost -SmtpPort $smtpPort -ConnectTimeoutMs 8000
  $networkStream = $tcpClient.GetStream()
  $reader = New-SmtpTextReader $networkStream
  $writer = New-SmtpTextWriter $networkStream
  $null = Read-SmtpReply -Reader $reader -ExpectedCodes @(220) -Stage 'greeting'
  $ehloReply = Send-SmtpCommand -Writer $writer -Reader $reader -Command 'EHLO hereiam.local' -ExpectedCodes @(250) -Stage 'EHLO'
  $startTlsOffered = $false
  foreach ($replyLine in $ehloReply.Lines) {
    if ($replyLine.Length -ge 4) {
      $capability = $replyLine.Substring(4)
      if ($capability.Equals('STARTTLS', [System.StringComparison]::OrdinalIgnoreCase) -or
          $capability.StartsWith('STARTTLS ', [System.StringComparison]::OrdinalIgnoreCase)) {
        $startTlsOffered = $true
      }
    }
  }
  if (-not $startTlsOffered) { throw 'SMTP server did not advertise STARTTLS.' }
  $null = Send-SmtpCommand -Writer $writer -Reader $reader -Command 'STARTTLS' -ExpectedCodes @(220) -Stage 'STARTTLS'

  $writer.Dispose()
  $reader.Dispose()
  $writer = $null
  $reader = $null

  # Keep certificate retrieval out of Cryptnet. The callback first requires the
  # built-in hostname/base-chain result, then performs bounded CRL retrieval and
  # a cache-only native Crypt32 revocation + SSL policy validation.
  $certificateValidation = New-StrictSmtpTlsValidationCallback `
    -ServerName $smtpHost `
    -DownloadBudgetMs 12000
  $sslStream = [System.Net.Security.SslStream]::new(
    $networkStream,
    $true,
    $certificateValidation
  )
  # The original hostname is required here for SNI and certificate validation;
  # the resolved IPv4 address is used only by the TCP connection above.
  $tlsHandshake = $sslStream.BeginAuthenticateAsClient(
    $smtpHost,
    $null,
    [System.Security.Authentication.SslProtocols]::Tls12,
    $false,
    $null,
    $null
  )
  try {
    # The manual hard-fail validation callback may need time to fetch signed CRLs.
    # Let the handshake use up to twenty seconds while Get-TransportRemainingMs
    # still enforces the 35-second total transport budget.
    $tlsWaitMs = Get-TransportRemainingMs 20000
    if (-not $tlsHandshake.AsyncWaitHandle.WaitOne($tlsWaitMs)) {
      throw 'SMTP TLS handshake timed out.'
    }
    $sslStream.EndAuthenticateAsClient($tlsHandshake)
  } finally {
    $tlsHandshake.AsyncWaitHandle.Close()
  }
  $reader = New-SmtpTextReader $sslStream
  $writer = New-SmtpTextWriter $sslStream
  $null = Send-SmtpCommand -Writer $writer -Reader $reader -Command 'EHLO hereiam.local' -ExpectedCodes @(250) -Stage 'post-TLS EHLO'
  $null = Send-SmtpCommand -Writer $writer -Reader $reader -Command 'AUTH LOGIN' -ExpectedCodes @(334) -Stage 'AUTH username challenge'

  $usernameBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$networkCredential.UserName)
  try {
    $usernameToken = [Convert]::ToBase64String($usernameBytes)
    $null = Send-SmtpCommand -Writer $writer -Reader $reader -Command $usernameToken -ExpectedCodes @(334) -Stage 'AUTH password challenge'
  } finally {
    [System.Array]::Clear($usernameBytes, 0, $usernameBytes.Length)
    $usernameToken = $null
  }

  $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$networkCredential.Password)
  try {
    $passwordToken = [Convert]::ToBase64String($passwordBytes)
    $null = Send-SmtpCommand -Writer $writer -Reader $reader -Command $passwordToken -ExpectedCodes @(235) -Stage 'AUTH'
  } finally {
    [System.Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
    $passwordToken = $null
  }

  $envelopeResult = Invoke-SmtpEnvelope `
    -Writer $writer `
    -Reader $reader `
    -Sender $sender `
    -Recipient $recipient `
    -MessageLines $messageLines `
    -AuthenticationProbe:$AuthenticationProbe
  $envelopeResult | ConvertTo-Json -Compress
} finally {
  try { if ($null -ne $writer) { $writer.Dispose() } } catch {}
  try { if ($null -ne $reader) { $reader.Dispose() } } catch {}
  try { if ($null -ne $sslStream) { $sslStream.Dispose() } } catch {}
  try { if ($null -ne $networkStream) { $networkStream.Dispose() } } catch {}
  try { if ($null -ne $tcpClient) { $tcpClient.Dispose() } } catch {}
  try {
    $networkCredential.Password = $null
    $networkCredential.UserName = $null
  } catch {}
}
