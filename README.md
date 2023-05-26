# vmware-snapshot-report
Set the following variables prior to running the snapshot-report.ps1
## Output filename
```
$filename = "snapshot-report.html"
```
## Ignore specific virtual machines, snapshot names, or snapshot descriptions
```
$ignorevms = "@!"
$ignorenames = "@!"
$ignoredescription = "@!"
```

## Array of Virtual Centre servers
```
$viservers = @('vc.domain.local', 'vc2.domain.local')
```

## Virtual Centre Credentails
```
$User = "username@vsphere.local"
$Password = "Password01"

$PWord = ConvertTo-SecureString -String $Password -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
```
