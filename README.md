# Badger RTU Bistate Monitor for PRTG

Learn how this PowerShell script can enable you to keep using your Badger 481 remotes while transitioning to new RTUs.
The script connects to a Badger RTU (Remote Terminal Unit) via a TCP serial server, reads bistate point alarm values, and returns XML output formatted for PRTG Network Monitor. This barely scratches the surface of fully utilizing the Badger 481 protocol. I only needed to integrate the binary inputs into PRTG, so I used a protocol analyzer to observe a functioning system and extract the necessary information to accomplish this.

<img width="1116" height="712" alt="image" src="https://github.com/user-attachments/assets/3f27d058-9833-49b5-ad93-445faab2e4c9" />


## Features

- Connects to a Badger RTU over TCP/IP via a common serial server device.
- Reads bistate point values (1–32)  
- Supports custom channel names via CSV  
- Implements retry logic for robust communication  
- Outputs XML compatible with PRTG custom sensors  

## Parameters

| Parameter        | Description                                | Example                      |
|------------------|--------------------------------------------|------------------------------|
| `-badgerAddress` | Address of the Badger RTU                  | `-badgerAddress 3`           |
| `-remoteIP`      | IP address of the TCP serial server        | `-remoteIP "10.123.123.111"` |
| `-remotePort`    | TCP port of the serial server              | `-remotePort 2107`           |

## Retry Logic

The script attempts to connect and communicate with the Badger up to **4 times** (1 initial attempt + 3 retries).  
If all attempts fail, it returns an error in XML format for PRTG to process.

## CSV Channel Mapping

Place a CSV file named like `*-<BadgerAddress>.csv` in the `Badger_Points` folder.  
The script reads channel names from this file, skipping the first two lines (metadata and blank).  
Points labeled `"SPARE"` are ignored.

## Example Usage

### Manual Testing

```powershell
# Channel 1
.\BadgerPRTG.ps1 -badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2107

# Channel 2
.\BadgerPRTG.ps1 -badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2108
```

### PRTG Parameters

Set the parameters in PRTG as:
```
-badgerAddress 3 -remoteIP "10.123.123.111" -remotePort 2107
```

## License

This script is provided as-is without warranty. You may modify and distribute it under your organization's policy or internal license terms.
