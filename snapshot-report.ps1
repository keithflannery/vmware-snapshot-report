
function Measure-TimeSince {
    param (
        [DateTime]$StartDate
    )

    # Calculate the time since the start date
    $TimeSince = New-TimeSpan -Start $StartDate -End (Get-Date)

    # Calculate the years, months, days, hours, and minutes since the start date
    $Years = [int]($TimeSince.Days / 365)
    $Months = [int]($TimeSince.Days % 365 / 30)
    $Days = [int]($TimeSince.Days % 365 % 30)
    $Hours = [int]$TimeSince.Hours
    $Minutes = [int]$TimeSince.Minutes

    # Select the most appropriate time unit based on the elapsed time
    if ($Years -gt 0) {
        $Output = "{0} year{1}" -f $Years, ('s' * ($Years -gt 1))
    }
    elseif ($Months -gt 0) {
        $Output = "{0} month{1}" -f $Months, ('s' * ($Months -gt 1))
    }
    elseif ($Days -gt 0) {
        $Output = "{0} day{1}" -f $Days, ('s' * ($Days -gt 1))
    }
    elseif ($Hours -gt 0) {
        $Output = "{0} hour{1}" -f $Hours, ('s' * ($Hours -gt 1))
    }
    else {
        $Output = ""
    }

    # If appropriate, add the number of minutes to the output string
    if ($Output -eq "" -and $Minutes -gt 0) {
        $Output += "{0} minute{1}" -f $Minutes, ('s' * ($Minutes -gt 1))
    }

    # Return the output string
    return $Output
}


Function Get-VMFolderPath {

    param([string]$VMFolderId)
    
    $Folders = [system.collections.arraylist]::new()
    $tracker = Get-Folder -Id $VMFolderId
    $Obj = [pscustomobject][ordered]@{FolderName = $tracker.Name; FolderID = $tracker.Id }
    $null = $Folders.add($Obj)
    
    while ($tracker) {
        if ($tracker.parent.type) {
            $tracker = (Get-Folder -Id $tracker.parentId)
            $Obj = [pscustomobject][ordered]@{FolderName = $tracker.Name; FolderID = $tracker.Id }
            $null = $Folders.add($Obj)
        }
        else {
            $Obj = [pscustomobject][ordered]@{FolderName = $tracker.parent.name; FolderID = $tracker.parentId }
            $null = $Folders.add($Obj)
            $tracker = $null
        }
    }
    $Folders.Reverse()
    $Folders.FolderName -join "/"
}

# URLDecode function
function URLDecode {
    param(
        [string]$string
    )
    $string = [System.Net.WebUtility]::UrlDecode($string)
    # if $string has %2f in it, replace with /
    if ($string -match '%2f') {
        $string = $string -replace '%2f', '/'
    }
    return $string
}

# Function to return a calculation of days since date
function Get-Age {
    param(
        [DateTime]$date
    )
    $age = $null

    $days = (Get-Date).Subtract($date).Days

    # if $days is less than 1, return hours
    if ($days -lt 1) {
        $hours = (Get-Date).Subtract($date).Hours
        $age = $hours.ToString() + " hours"
    }
    else {
        $age = $days.ToString() + " days"
    }

    return $age

}


function Get-SnapshotInfo {
    param(
        [VMware.Vim.VirtualMachineSnapshotTree]$Tree
    )
    
    $vm = Get-View -Id $Tree.VM
    
    $entry = $vm.LayoutEx.Snapshot | Where-Object { $_.Key -eq $Tree.Snapshot }
    $files = $vm.LayoutEx.File | Where-Object { ($entry.Disk | ForEach-Object { $_.Chain[-1] }).FileKey -contains $_.Key }

    # URL Decode Name
    $name = (URLDecode -string $Tree.Name)
    # Age of snapshot in days
    $age = Measure-TimeSince $Tree.CreateTime.addhours(10)
    # Get Snapshot Creator
    # $createdby = Get-SnapshotCreator -snapshot $Tree

    # Write-Host $createdby

    New-Object -TypeName PSObject -Property @{
        Name        = $name
        Description = $Tree.Description
        Created     = $Tree.CreateTime
        CreatedDate = $Tree.CreateTime
        Age         = $age
        SizeGB      = [math]::Round(($files | Measure-Object -Property Size -Sum).Sum / 1GB, 2)
        
    }
    if ($Tree.ChildSnapshotList) {
        $Tree.ChildSnapshotList | ForEach-Object -Process {
            Get-SnapshotInfo -Tree $_
        }
    }
}

# Function to return an array of VMs with snapshots
function Get-VMsWithSnapshots {
    $vms = Get-VM | Get-Snapshot | Select-Object VM | Sort-Object VM -Unique 

    return $vms
}



# Function to reformat date to Australian format
function Format-AUDate {
    param(
        $date
    )
    if ($date.GetType() -eq [DateTime]) {
        $date = (Get-Date $date -Format "d/M/yyyy h:mm tt")
    }
    else {
        $date = [DateTime]::ParseExact($date, 'd/M/yyyy h:mm tt', $null)
    }
    


    return $date
}

# Function getting the snapshot creator
function Get-SnapshotCreator {
    param(
        $snapshot
    )
    $creator = $null
    
    $snapevent = Get-VIEvent -Entity $snapshot.VM -Types Info -Finish $snapshot.CreatedDate -MaxSamples 1 | Where-Object { $_.FullFormattedMessage -imatch ‘Task: Create virtual machine snapshot’ }
    if ($snapevent -ne $null) {
        $creator = $snapevent.UserName
    }

    return $creator
}



$ignorevms = "@!"
$ignorenames = "@!"
$ignoredescription = "@!"

Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope Session -Confirm:$false
Set-PowerCLIConfiguration -Scope Session -ParticipateInCEIP $true -Confirm:$false

$snapshotlist = @()


# Loop over each vCenter server
foreach ($viserver in $viservers) {
    # Connect to vCenter server
    Connect-VIServer -Server $viserver -Credential $credential

    # Get list of VMs with snapshots
    $vms = Get-VMsWithSnapshots

    # Loop over each VM with snapshots
    foreach ($vm in $vms) {
        $vminfo = get-vm -Name $vm.VM

        $vminfo.ExtensionData.Snapshot.RootSnapshotList |
        ForEach-Object -Process {
            $snapshotinfo = Get-SnapshotInfo -Tree $_
        }
        
        try {
            $folder = Get-VMFolderPath $vminfo.Folder.Id
        }
        catch {
            $folder = "No Folder"
        }

            
        # Exclude the VMs with the following criteria
        foreach ($snapshot in $snapshotinfo) {
            if ($snapshot.Name -in $ignorenames) {
                Continue
            }
            if ($vminfo.Name -in $ignorevms) {
                Continue
            }
            if ($snapshot.Description -match $ignoredescription) {
                Continue
            }
            # Get the snapshot creator
            $createdby = "event purged"
            $snapevent = Get-VIEvent -Entity $vminfo.Name -Types Info -Finish $snapshot.Created -MaxSamples 1 | Where-Object { $_.FullFormattedMessage -imatch ‘Task: Create virtual machine snapshot’ }
            
            if ($snapevent -ne $null) {
                $createdby = $snapevent.UserName
            }
            # Change date format to a sane one!
            $displaydate = Format-AUDate -date $snapshot.Created.AddHours(10)

            $ss = New-Object -TypeName PSObject -Property @{
                VM              = $vminfo.Name
                "Snapshot Name" = $snapshot.Name
                Description     = $snapshot.Description
                Created         = $displaydate
                Age             = $snapshot.Age
                SizeGB          = $snapshot.SizeGB
                Folder          = $folder
                VApp            = $vminfo.VApp.Name
                "Created By"    = $createdby
                VCSA            = $viserver
            }
            $snapshotlist += $ss
        
        }

    }
    Disconnect-VIServer -Server $viserver -Confirm:$false
}

$snapshotlist | Select-Object VM, Folder, VApp, "Snapshot Name", Description, VCSA, Created, Age, SizeGB, "Created By" | Sort-Object -Property VCSA, Age -Descending | Format-Table -AutoSize


$css = @"
<style>
    table {
        border-collapse: collapse;
        width: 100%;
        font-family: Calibri, sans-serif;
        font-size: 11pt;
        color: #333;
        border: 1px solid #ccc;
    }
    th, td {
        padding: 6px 8px;
        text-align: left;
        border: 1px solid #ccc;
    }
    th {
        background-color: #1F497D;
        color: #fff;
        font-weight: bold;
    }
    tr:nth-child(even) td {
        background-color: #F2F2F2;
    }
    tr:hover td {
        background-color: #D9E1F2;
    }
</style>
"@


$snapshotlist | Select-Object VM, Folder, VApp, "Snapshot Name", Description, VCSA, Created, Age, SizeGB, "Created By" | Sort-Object -Property VCSA, Age -Descending | convertto-html -Head $css | out-file $filename
