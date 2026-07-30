# Generate-RemoteKubeconfig.ps1
# Creates a kubeconfig file for accessing the Kubernetes cluster from external machines

param(
    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "cluster5",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "kubeconfig-remote",
    
    [Parameter(Mandatory=$false)]
    [string]$ManualIP = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipTLSVerify
)

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Remote Kubeconfig Generator" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Check if kubeconfig exists
$localKubeconfig = ".\kubeconfig"
if (-not (Test-Path $localKubeconfig)) {
    Write-Host "ERROR: kubeconfig file not found in current directory" -ForegroundColor Red
    Write-Host "Make sure you run this script in the same directory as your Vagrantfile" -ForegroundColor Yellow
    Write-Host "and that you've run 'vagrant up' to create the cluster" -ForegroundColor Yellow
    exit 1
}

Write-Host "[1/4] Found local kubeconfig file" -ForegroundColor Green

# Get control plane node's public IP address
Write-Host "[2/4] Retrieving control plane node's public IP address..." -ForegroundColor Yellow

$cpNodeName = "$ClusterName-control-plane"

# Check if manual IP was provided
if ($ManualIP) {
    Write-Host "       Using manually specified IP: $ManualIP" -ForegroundColor Green
    $cpIP = $ManualIP
} else {
    # Check if VM is running
    $vmStatus = vagrant status $cpNodeName 2>$null | Select-String "running"
    if (-not $vmStatus) {
        Write-Host "ERROR: Control plane node '$cpNodeName' is not running" -ForegroundColor Red
        Write-Host "Start it with: vagrant up $cpNodeName" -ForegroundColor Yellow
        exit 1
    }

    # Get the public IP from the control plane node
    # Try multiple common interface names and methods
    Write-Host "       Trying to detect public IP from control plane node..." -ForegroundColor Gray

    # Method 1: Try common bridged adapter names
    $ipCommand = @"
for iface in enp0s8 eth1 enp0s9 eth2; do
    ip -4 addr show `$iface 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 && break
done
"@

    $rawOutput = vagrant ssh $cpNodeName -c $ipCommand 2>&1
    $cpIP = $rawOutput | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' } | Select-Object -First 1

    # Method 2: If first method fails, try getting all non-loopback IPs except 10.0.2.x (NAT)
    if (-not $cpIP) {
        Write-Host "       Trying alternative detection method..." -ForegroundColor Gray
        $ipCommand = "ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^10\.0\.2\.' | grep -v '^10\.0\.0\.'"
        $rawOutput = vagrant ssh $cpNodeName -c $ipCommand 2>&1
        $cpIP = $rawOutput | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' } | Select-Object -First 1
    }

    if (-not $cpIP -or [string]::IsNullOrWhiteSpace($cpIP)) {
        Write-Host "ERROR: Could not retrieve control plane node's public IP address" -ForegroundColor Red
        Write-Host ""
        Write-Host "Debug information:" -ForegroundColor Yellow
        Write-Host "Raw output from VM:" -ForegroundColor Gray
        $rawOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Check if the control plane node has a bridged network adapter:" -ForegroundColor Yellow
        Write-Host "   vagrant ssh $cpNodeName" -ForegroundColor Gray
        Write-Host "   ip addr show" -ForegroundColor Gray
        Write-Host ""
        Write-Host "2. Look for a network interface with an IP on your local network" -ForegroundColor Yellow
        Write-Host "   (NOT 10.0.2.x which is the NAT network)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "3. If you see a public IP, use the -ManualIP parameter:" -ForegroundColor Yellow
        Write-Host "   .\Generate-RemoteKubeconfig.ps1 -ManualIP '192.168.x.x'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "4. If no public IP exists, ensure the Vagrantfile has:" -ForegroundColor Yellow
        Write-Host "   node.vm.network `"public_network`"" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }

    $cpIP = $cpIP.Trim()
}

# Validate IP address format
if ($cpIP -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    Write-Host "ERROR: Invalid IP address retrieved: $cpIP" -ForegroundColor Red
    exit 1
}

Write-Host "       Control plane node public IP: $cpIP" -ForegroundColor Green
Write-Host ""

# Read and modify the kubeconfig
Write-Host "[3/4] Generating remote kubeconfig..." -ForegroundColor Yellow

try {
    $kubeconfigContent = Get-Content $localKubeconfig -Raw
    
    # Replace the private IP with public IP
    $remoteKubeconfig = $kubeconfigContent -replace 'https://10\.0\.0\.\d+:6443', "https://${cpIP}:6443"
    
    # Add insecure-skip-tls-verify if requested
    if ($SkipTLSVerify) {
        Write-Host "       Adding insecure-skip-tls-verify flag" -ForegroundColor Yellow
        # Add insecure-skip-tls-verify to the cluster config
        $remoteKubeconfig = $remoteKubeconfig -replace '(  - cluster:)', "`$1`n    insecure-skip-tls-verify: true"
        # Remove certificate-authority-data if it exists (optional when skipping TLS)
        $remoteKubeconfig = $remoteKubeconfig -replace '\s*certificate-authority-data:.*\n', "`n"
    }
    
    # Write to output file
    Set-Content -Path $OutputFile -Value $remoteKubeconfig -NoNewline
    Write-Host "       Remote kubeconfig created: $OutputFile" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "ERROR: Failed to generate remote kubeconfig" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Display next steps
Write-Host "[4/4] Setup Instructions" -ForegroundColor Yellow
Write-Host ""
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

if (-not $SkipTLSVerify) {
    Write-Host "IMPORTANT: Add this entry to your hosts file on the remote machine:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  $cpIP $cpNodeName" -ForegroundColor White
    Write-Host ""
    Write-Host "Windows (run as Administrator):" -ForegroundColor Cyan
    Write-Host "  Add-Content C:\Windows\System32\drivers\etc\hosts `"``n$cpIP $cpNodeName`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Linux/Mac:" -ForegroundColor Cyan
    Write-Host "  echo `"$cpIP $cpNodeName`" | sudo tee -a /etc/hosts" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Transfer the kubeconfig file to your remote machine:" -ForegroundColor Yellow
Write-Host "  File: $OutputFile" -ForegroundColor White
Write-Host ""

Write-Host "On the remote machine, set the KUBECONFIG environment variable:" -ForegroundColor Yellow
Write-Host ""
Write-Host "PowerShell:" -ForegroundColor Cyan
Write-Host "  `$env:KUBECONFIG=`"C:\path\to\$OutputFile`"" -ForegroundColor Gray
Write-Host "  kubectl get nodes" -ForegroundColor Gray
Write-Host ""
Write-Host "Linux/Mac:" -ForegroundColor Cyan
Write-Host "  export KUBECONFIG=/path/to/$OutputFile" -ForegroundColor Gray
Write-Host "  kubectl get nodes" -ForegroundColor Gray
Write-Host ""

Write-Host "Test connectivity from remote machine:" -ForegroundColor Yellow
Write-Host "  Test-NetConnection -ComputerName $cpIP -Port 6443" -ForegroundColor Gray
Write-Host ""

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Generation Complete!" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Cyan