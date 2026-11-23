$ErrorActionPreference = 'Continue'
$root = 'd:\Downloads\ChemNote'
$docsRoot = Join-Path $root 'docs'
$port = 8080

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.ico'  = 'image/x-icon'
  '.apk'  = 'application/vnd.android.package-archive'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
$listener.Start()
Write-Output "[OK] ChemNote Pro v3.0.0 Wi-Fi & Local HTTP Server listening on 0.0.0.0:$port"

while ($true) {
  $client = $null
  try {
    $client = $listener.AcceptTcpClient()
    $client.ReceiveTimeout = 5000
    $client.SendTimeout = 10000
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrEmpty($requestLine)) {
      $client.Close()
      continue
    }

    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq '') { break }
    }

    $parts = $requestLine.Split(' ')
    $method = if ($parts.Length -ge 1) { $parts[0].ToUpper() } else { 'GET' }
    $rawUrl = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
    $urlPath = ($rawUrl -split '\?')[0]
    $urlPath = [System.Uri]::UnescapeDataString($urlPath).TrimStart('/')

    if ([string]::IsNullOrEmpty($urlPath)) {
      $urlPath = 'index.html'
    }

    if ($urlPath -eq 'favicon.ico') {
      $iconSvg = Join-Path $docsRoot 'icon.svg'
      if (Test-Path $iconSvg -PathType Leaf) {
        $bodyBytes = [System.IO.File]::ReadAllBytes($iconSvg)
        $header = "HTTP/1.1 200 OK`r`nContent-Type: image/svg+xml`r`nContent-Length: $($bodyBytes.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
        $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($hBytes, 0, $hBytes.Length)
        if ($method -ne 'HEAD') { $stream.Write($bodyBytes, 0, $bodyBytes.Length) }
      } else {
        $header = "HTTP/1.1 204 No Content`r`nConnection: close`r`nContent-Length: 0`r`n`r`n"
        $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($hBytes, 0, $hBytes.Length)
      }
      $stream.Flush()
      $client.Close()
      continue
    }

    $safeRel = ($urlPath -replace '/', '\') -replace '\.\.', ''
    $docsCandidate = Join-Path $docsRoot $safeRel
    $rootCandidate = Join-Path $root $safeRel

    $filePath = $null
    if (Test-Path $docsCandidate -PathType Leaf) {
      $filePath = $docsCandidate
    } elseif (Test-Path $rootCandidate -PathType Leaf) {
      $filePath = $rootCandidate
    }

    if ($null -ne $filePath) {
      $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
      $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $bodyBytes = [System.IO.File]::ReadAllBytes($filePath)
      $header = "HTTP/1.1 200 OK`r`n" +
                "Content-Type: $contentType`r`n" +
                "Content-Length: $($bodyBytes.Length)`r`n" +
                "Cache-Control: no-cache, no-store, must-revalidate`r`n" +
                "Access-Control-Allow-Origin: *`r`n" +
                "Connection: close`r`n`r`n"
      $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($hBytes, 0, $hBytes.Length)
      if ($method -ne 'HEAD') {
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
      }
    } else {
      $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")
      $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($notFound.Length)`r`nConnection: close`r`n`r`n"
      $hBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($hBytes, 0, $hBytes.Length)
      if ($method -ne 'HEAD') {
        $stream.Write($notFound, 0, $notFound.Length)
      }
    }
    $stream.Flush()
  } catch {
    # Ignore individual client socket drops
  } finally {
    if ($null -ne $client) {
      try { $client.Close() } catch {}
    }
  }
}
