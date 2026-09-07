# Split Metronome local server.
# Serves this folder over HTTP on the local network so a phone can open the app,
# and answers mDNS (Bonjour) so the phone can use the name below instead of an IP.
# Needs nothing but Windows PowerShell. Press Ctrl+C in this window to stop.

$name  = 'metro'          # phone opens http://metro.local:PORT
$ports = 8765, 8766, 8767, 8768

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fqdn = "$name.local"
$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.json' = 'application/manifest+json'
  '.png'  = 'image/png'
  '.css'  = 'text/css; charset=utf-8'
  '.txt'  = 'text/plain; charset=utf-8'
  '.ico'  = 'image/x-icon'
}

# ---- find this computer's network addresses (the one with the default route first) ----
function Get-LanAddresses {
  $found = @()
  try {
    $gwIf = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -ExpandProperty InterfaceIndex)
    $all = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
    $found = @($all | Sort-Object { if ($gwIf -contains $_.InterfaceIndex) { 0 } else { 1 } }, InterfaceIndex |
      ForEach-Object { [pscustomobject]@{ IP = $_.IPAddress; Name = $_.InterfaceAlias } })
  } catch {}
  if (-not $found) {
    try {
      $found = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -notlike '127.*' } |
        ForEach-Object { [pscustomobject]@{ IP = $_.IPAddressToString; Name = 'network' } })
    } catch {}
  }
  return $found
}

# ---- start the web server ----
function Test-PortBusy([int]$p) {
  # true if something already answers on this port (Windows lets some servers share a port, so we check first)
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $ar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
    $ok = $ar.AsyncWaitHandle.WaitOne(250)
    $busy = $ok -and $c.Connected
    $c.Close()
    return $busy
  } catch { return $false }
}
$listener = $null
$port = 0
foreach ($p in $ports) {
  if (Test-PortBusy $p) { continue }
  try {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $p)
    $l.ExclusiveAddressUse = $true
    $l.Start()
    $listener = $l; $port = $p; break
  } catch { }
}
if (-not $listener) { Write-Host "Could not open a port (tried $($ports -join ', ')). Close other servers and try again." -ForegroundColor Red; exit 1 }

$addrs = Get-LanAddresses
$lanIp = if ($addrs) { [System.Net.IPAddress]::Parse($addrs[0].IP) } else { $null }

# ---- start the mDNS responder (answers "metro.local" with this computer's address) ----
$udp = $null
$mcastEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('224.0.0.251'), 5353)
if ($lanIp) {
  try {
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.ExclusiveAddressUse = $false
    $udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $udp.Client.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 5353)))
    $udp.JoinMulticastGroup([System.Net.IPAddress]::Parse('224.0.0.251'), $lanIp)
    $udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP, [System.Net.Sockets.SocketOptionName]::MulticastInterface, $lanIp.GetAddressBytes())
    $udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP, [System.Net.Sockets.SocketOptionName]::MulticastTimeToLive, 255)
  } catch { $udp = $null }
}

function Read-DnsName([byte[]]$d, [int]$pos) {
  $labels = @(); $jumped = $false; $end = $pos; $guard = 0
  while ($pos -lt $d.Length) {
    $len = [int]$d[$pos]
    if ($len -eq 0) { $pos++; break }
    if (($len -band 0xC0) -eq 0xC0) {
      if ($pos + 1 -ge $d.Length) { break }
      $ptr = (($len -band 0x3F) -shl 8) -bor [int]$d[$pos + 1]
      if (-not $jumped) { $end = $pos + 2 }
      $jumped = $true; $pos = $ptr
      if (++$guard -gt 20) { break }
      continue
    }
    if ($pos + 1 + $len -gt $d.Length) { break }
    $labels += [System.Text.Encoding]::ASCII.GetString($d, $pos + 1, $len)
    $pos += 1 + $len
  }
  if (-not $jumped) { $end = $pos }
  return @{ Name = ($labels -join '.'); Next = $end }
}

$script:lastMdnsLog = [DateTime]::MinValue
function Handle-Mdns([byte[]]$d, [System.Net.IPEndPoint]$from) {
  if ($d.Length -lt 12) { return }
  $flags = ([int]$d[2] -shl 8) -bor [int]$d[3]
  if (($flags -band 0x8000) -ne 0) { return }          # that is a response, not a question
  $qd = ([int]$d[4] -shl 8) -bor [int]$d[5]
  $pos = 12; $hit = $false
  for ($i = 0; $i -lt $qd; $i++) {
    $r = Read-DnsName $d $pos; $pos = [int]$r.Next
    if ($pos + 4 -gt $d.Length) { break }
    $qtype = ([int]$d[$pos] -shl 8) -bor [int]$d[$pos + 1]
    $pos += 4
    if ($r.Name.ToLower() -eq $fqdn -and ($qtype -eq 1 -or $qtype -eq 255)) { $hit = $true }
  }
  if (-not $hit) { return }

  $legacy = ($from.Port -ne 5353)                      # plain DNS client asking on a random port
  $b = New-Object System.Collections.Generic.List[byte]
  if ($legacy) { $b.Add($d[0]); $b.Add($d[1]) } else { $b.Add(0); $b.Add(0) }
  $b.Add(0x84); $b.Add(0x00)                           # response, authoritative
  $b.Add(0); $b.Add(0)                                 # questions
  $b.Add(0); $b.Add(1)                                 # answers
  $b.Add(0); $b.Add(0); $b.Add(0); $b.Add(0)
  foreach ($lab in $fqdn.Split('.')) { $b.Add([byte]$lab.Length); $b.AddRange([System.Text.Encoding]::ASCII.GetBytes($lab)) }
  $b.Add(0)
  $b.Add(0); $b.Add(1)                                 # type A
  if ($legacy) { $b.Add(0); $b.Add(1) } else { $b.Add(0x80); $b.Add(1) }   # class IN (+cache flush for mDNS)
  $ttl = if ($legacy) { 10 } else { 120 }
  $b.Add(0); $b.Add(0); $b.Add([byte](($ttl -shr 8) -band 0xFF)); $b.Add([byte]($ttl -band 0xFF))
  $b.Add(0); $b.Add(4)
  $b.AddRange($lanIp.GetAddressBytes())
  $bytes = $b.ToArray()
  if ($legacy) { [void]$udp.Send($bytes, $bytes.Length, $from) } else { [void]$udp.Send($bytes, $bytes.Length, $mcastEP) }
  if (([DateTime]::Now - $script:lastMdnsLog).TotalSeconds -gt 3) {
    Write-Host ("  {0}  {1,-15}  name  {2} -> {3}" -f (Get-Date -Format 'HH:mm:ss'), $from.Address, $fqdn, $lanIp) -ForegroundColor DarkCyan
    $script:lastMdnsLog = [DateTime]::Now
  }
}

# ---- banner ----
$host.UI.RawUI.WindowTitle = "Split Metronome server  -  port $port"
Clear-Host
Write-Host ''
Write-Host '  SPLIT METRONOME  -  server is running' -ForegroundColor Green
Write-Host ''
Write-Host '  On your phone (same Wi-Fi as this computer) open:' -ForegroundColor White
Write-Host ''
if ($udp) {
  Write-Host "      http://$fqdn`:$port" -ForegroundColor Yellow -NoNewline
  Write-Host '     <- easiest (iPhone, iPad, Mac, most Android)' -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  If that name does not open, use the address instead:' -ForegroundColor White
} else {
  Write-Host '  (name lookup could not start, use the address)' -ForegroundColor DarkYellow
}
if ($addrs) {
  $first = $true
  foreach ($a in $addrs) {
    $url = "http://$($a.IP):$port"
    if ($first) { Write-Host "      $url" -ForegroundColor Yellow -NoNewline; Write-Host "     ($($a.Name))" -ForegroundColor DarkGray }
    else        { Write-Host "      $url" -ForegroundColor Gray   -NoNewline; Write-Host "     ($($a.Name))" -ForegroundColor DarkGray }
    $first = $false
  }
} else {
  Write-Host "      Could not read this computer's IP address. Run  ipconfig  and use the IPv4 address with port $port" -ForegroundColor Red
}
Write-Host ''
Write-Host '  If Windows Firewall asks, click Allow access (Private networks).' -ForegroundColor DarkGray
Write-Host '  Keep this window open while you use the app. Press Ctrl+C to stop.' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  --- activity ---' -ForegroundColor DarkGray

$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'

function Send-Response($stream, [int]$code, [string]$reason, [string]$type, [byte[]]$body) {
  $head = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
  $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($hb, 0, $hb.Length)
  if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
  $stream.Flush()
}

function Handle-Http($client) {
  try {
    $client.ReceiveTimeout = 3000
    $client.SendTimeout = 15000
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
    $request = $reader.ReadLine()
    while ($true) { $h = $reader.ReadLine(); if ($null -eq $h -or $h -eq '') { break } }
    if (-not $request) { return }

    $parts = $request -split ' '
    $path = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
    $path = ($path -split '\?')[0]
    $path = [System.Uri]::UnescapeDataString($path)
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }

    $rel = $path.TrimStart('/') -replace '/', '\'
    $file = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
    $who = $client.Client.RemoteEndPoint.Address.ToString()

    if ($file.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $bytes = [System.IO.File]::ReadAllBytes($file)
      Send-Response $stream 200 'OK' $type $bytes
      Write-Host ("  {0}  {1,-15}  200   {2}" -f (Get-Date -Format 'HH:mm:ss'), $who, $path) -ForegroundColor DarkGreen
    } else {
      $nf = [System.Text.Encoding]::UTF8.GetBytes('Not found')
      Send-Response $stream 404 'Not Found' 'text/plain' $nf
      Write-Host ("  {0}  {1,-15}  404   {2}" -f (Get-Date -Format 'HH:mm:ss'), $who, $path) -ForegroundColor DarkYellow
    }
  } catch {
    # a dropped connection is normal on phones; keep serving
  } finally {
    try { $client.Close() } catch {}
  }
}

# ---- main loop: web requests and name questions, forever ----
while ($true) {
  $did = $false
  if ($listener.Pending()) { Handle-Http $listener.AcceptTcpClient(); $did = $true }
  if ($udp) {
    while ($udp.Available -gt 0) {
      $from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
      try { $data = $udp.Receive([ref]$from); Handle-Mdns $data $from } catch {}
      $did = $true
    }
  }
  if (-not $did) { Start-Sleep -Milliseconds 5 }
}
