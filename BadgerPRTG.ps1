# PRTG Sensor Script for Badger Bistate Points via TCP Serial Server
# Set Parameters in PRTG to: <BadgerAddress> <RemoteIP> <RemotePort>    Example: -badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2107
# To test manually CH1   .\BadgerPRTG.ps1 -badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2107
# To test manually CH2   .\BadgerPRTG.ps1 -badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2108
# Don't forget to use Mutex Name in PRTG so devices get polled round robin and not all at once.  eg.: badgerCH1 or badgerCH2
# This script will also attempt to read a CVS file from a folder named Badger_Points within the same script directory to pre-name your Badger Channels in the format of xxxxx-##.csv  
# where xxxxx is any text and ## is the badger address.
# https://github.com/pir8radio/PRTG-Badger-481-Sensor-Script

param (
    [string]$badgerAddress,
    [string]$remoteIP = "192.168.1.100",
    [int]$remotePort = 4001
)

function CalculateLRC {
    param ([byte[]]$data)
    $lrc = 0
    foreach ($byte in $data) {
        $lrc = $lrc -bxor $byte
    }
    return [byte]$lrc
}

function Send-Command {
    param (
        [System.Net.Sockets.NetworkStream]$stream,
        [byte[]]$command
    )
    Write-Host "Sending: $($command -join ' ')"
    $stream.Write($command, 0, $command.Length)
    Start-Sleep -Milliseconds 100

    $response = New-Object byte[] 7
    $bytesRead = $stream.Read($response, 0, $response.Length)
    Write-Host "Received ($bytesRead bytes): $($response[0..($bytesRead-1)] -join ' ')"
    return $response[0..($bytesRead-1)]
}

try {
    # Load custom channel names from CSV
    $channelNames = @{}
    $pointsFolder = Join-Path $PSScriptRoot "Badger_Points"
    $pattern = "*-$badgerAddress.csv"
    $csvFile = Get-ChildItem -Path $pointsFolder -Filter *.csv | Where-Object {
        $name = $_.Name.ToLower()
        $pattern | Where-Object { $name -like $_.ToLower() }
    } | Select-Object -First 1

    if ($csvFile) {
        $lines = Get-Content -Path $csvFile.FullName
        $csvText = ($lines | Select-Object -Skip 2) -join "`n"
        $csvContent = $csvText | ConvertFrom-Csv

        foreach ($row in $csvContent) {
            $point = [int]$row.PointNumber
            $desc = ($row.PointName -as [string]).Trim()
            if ($point -ge 1 -and $point -le 32 -and $desc -and $desc -notmatch 'SPARE') {
                $channelNames[$point] = $desc
            }
        }
    }

    for ($i = 1; $i -le 32; $i++) {
        if (-not $channelNames.ContainsKey($i)) {
            $channelNames[$i] = "Point $i"
        }
    }

    $C_RGN_RN1 = 0x8E
    $C_RGN_RN2 = 0x8F

    $command1 = [System.Collections.Generic.List[byte]]::new()
    $command1.Add([byte]$C_RGN_RN1)
    $command1.Add([byte]$badgerAddress)
    $command1.Add((CalculateLRC -data $command1.ToArray()))

    $command2 = [System.Collections.Generic.List[byte]]::new()
    $command2.Add([byte]$C_RGN_RN2)
    $command2.Add([byte]$badgerAddress)
    $command2.Add((CalculateLRC -data $command2.ToArray()))

    $maxRetries = 4    # How many times to try a unit if it fails
    $attempt = 0
    $success = $false

    while ($attempt -lt $maxRetries -and -not $success) {
        try {
            $attempt++
            Write-Host "Attempt $attempt to connect and communicate with Badger unit..."

            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect($remoteIP, $remotePort)
            $stream = $client.GetStream()
            $stream.ReadTimeout = 2000
            $stream.WriteTimeout = 2000

            $response1 = Send-Command -stream $stream -command $command1.ToArray()
            $response2 = Send-Command -stream $stream -command $command2.ToArray()

            $success = $true
        }
        catch {
            Write-Warning "Attempt $attempt failed: $($_.Exception.Message)"
            if ($stream) { $stream.Close() }
            if ($client) { $client.Close() }
            Start-Sleep -Seconds 1
        }
    }

    if (-not $success) {
        throw "Failed to communicate with Badger unit after $maxRetries attempts."
    }

    $stream.Close()
    $client.Close()

    $mask1 = $response1[2..5]
    $mask2 = $response2[2..5]
    $bitmask = $mask1 + $mask2

    [xml]$xml = New-Object System.Xml.XmlDocument
    $prtg = $xml.CreateElement("prtg")
    $xml.AppendChild($prtg) | Out-Null

    for ($i = 0; $i -lt 32; $i++) {
        $byteIndex = [math]::Floor($i / 8)
        $bitIndex = $i % 8
        $bit = ($bitmask[$byteIndex] -shr $bitIndex) -band 0x01

        $result = $xml.CreateElement("result")

        $channel = $xml.CreateElement("channel")
        $channel.InnerText = $channelNames[$i + 1]
        $result.AppendChild($channel) | Out-Null

        $val = $xml.CreateElement("value")
        $val.InnerText = $bit
        $result.AppendChild($val) | Out-Null

        $lookup = $xml.CreateElement("ValueLookup")
        $lookup.InnerText = "custom.lookup.1.alarm"
        $result.AppendChild($lookup) | Out-Null

        $prtg.AppendChild($result) | Out-Null
    }

    $xml.OuterXml
}
catch {
    if ($stream) { $stream.Close() }
    if ($client) { $client.Close() }

    [xml]$errorXml = New-Object System.Xml.XmlDocument
    $prtg = $errorXml.CreateElement("prtg")
    $errorXml.AppendChild($prtg) | Out-Null

    $errorNode = $errorXml.CreateElement("error")
    $errorNode.InnerText = "1"
    $prtg.AppendChild($errorNode) | Out-Null

    $textNode = $errorXml.CreateElement("text")
    $textNode.InnerText = "Error: $($_.Exception.Message)"
    $prtg.AppendChild($textNode) | Out-Null

    $errorXml.OuterXml
}
